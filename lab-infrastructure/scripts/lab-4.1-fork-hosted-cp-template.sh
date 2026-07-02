#!/usr/bin/env bash
#
# lab-4.1-fork-hosted-cp-template.sh
# ----------------------------------
# Fork the shipped `aws-hosted-cp` ClusterTemplate and pin the HOSTED control-plane
# k0s version to a build that contains the fix for k0s issue #7832 — the
# `ExtensionsReconciler` / "helm CRD is not registered" crashloop that bricks the
# hosted control plane on a stock k0rdent Enterprise 1.3.1 install.
#
#   Root cause   k0s #7832: the helm ExtensionsReconciler polls for the
#                charts.helm.k0sproject.io CRD with a 10-attempt cap (avast/retry-go
#                default) and fatally exits before the async CRD applier wins the race.
#                In a single-pod k0smotron control plane the race is 100% deterministic.
#   Fixed by     k0s PR #7217 — first shipped in v1.33.9 / v1.34.5 / v1.35.2 (never 1.32).
#   The problem  Enterprise 1.3.1 ships template aws-hosted-cp-1-0-29 -> k0s v1.35.1+k0s.1,
#                which is ONE patch release before the fix.
#   The fix      Fork the chart, bump k0s.version to v1.35.2+k0s.0, republish, and
#                register it as a new ClusterTemplate. (ClusterTemplates are immutable
#                and the k0s version is not a ClusterDeployment.config field, so a fork
#                is the supported path.)
#
# RUN THIS ON THE MANAGEMENT NODE (it needs helm, kubectl, aws, and KUBECONFIG set to
# the k0rdent management cluster). It is idempotent — safe to re-run.
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Config (override any of these via environment variables)
# ---------------------------------------------------------------------------
SRC_CHART="${SRC_CHART:-aws-hosted-cp}"                 # chart name to fork
SRC_CHART_VERSION="${SRC_CHART_VERSION:-1.0.29}"        # shipped chart version (Enterprise 1.3.1)
NEW_CHART_VERSION="${NEW_CHART_VERSION:-1.0.30}"        # MUST differ from the shipped version
FIXED_K0S_VERSION="${FIXED_K0S_VERSION:-v1.35.4+k0s.0}" # past k0s #7217 (>=1.35.2) AND present in
                                                        # the Mirantis Enterprise registry. NOTE: the
                                                        # upstream-minimal fix v1.35.2 is NOT in
                                                        # registry.mirantis.com (it only carries shipped
                                                        # builds: v1.35.1, v1.35.4). Verified live 2026-06-30.
NEW_TEMPLATE_NAME="${NEW_TEMPLATE_NAME:-aws-hosted-cp-fixed}"
NS="${NS:-kcm-system}"                                  # MUST match the ClusterDeployment namespace
HELMREPO_NAME="${HELMREPO_NAME:-lab-custom-templates}"
WORKDIR="${WORKDIR:-/tmp/hosted-cp-fork}"

# S3 bucket used to serve the forked chart as an HTTP Helm repo.
# A DEDICATED bucket — never the terraform-state bucket (that holds sensitive tfstate
# and must never be public). Defaults to "<student-bucket>-charts".
AWS_REGION="${AWS_REGION:?export AWS_REGION first}"
CHART_BUCKET="${CHART_BUCKET:-}"   # auto-derived below if empty

log()  { echo -e "\033[0;34m[fork]\033[0m $*"; }
ok()   { echo -e "\033[0;32m[ ok ]\033[0m $*"; }
warn() { echo -e "\033[0;33m[warn]\033[0m $*"; }
die()  { echo -e "\033[0;31m[fail]\033[0m $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------
command -v helm    >/dev/null || die "helm not found"
command -v kubectl >/dev/null || die "kubectl not found"
command -v aws     >/dev/null || die "aws CLI not found"
command -v yq      >/dev/null || die "yq not found"
kubectl get ns "$NS" >/dev/null 2>&1 || die "namespace $NS not found — is this the mgmt cluster?"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
if [[ -z "$CHART_BUCKET" ]]; then
  CHART_BUCKET="k0rdent-lab-charts-${ACCOUNT_ID}-${AWS_REGION}"
fi
mkdir -p "$WORKDIR"; cd "$WORKDIR"

# Sanity-confirm the CR API shape on THIS cluster (the runbook flagged version drift).
log "ClusterTemplate API on this cluster:"
kubectl explain clustertemplate.spec.helm 2>/dev/null | head -20 || warn "kubectl explain unavailable"

# ---------------------------------------------------------------------------
# 1. Discover the kcm chart source and pull the EXACT shipped chart
#    (forking the Enterprise-packaged chart avoids OSS image-registry drift)
# ---------------------------------------------------------------------------
log "Discovering the kcm template HelmRepository in $NS ..."
KCM_OCI_URL="$(kubectl get helmrepository -n "$NS" \
  -o jsonpath='{range .items[*]}{.spec.url}{"\n"}{end}' 2>/dev/null | grep -m1 'oci://' || true)"
[[ -n "$KCM_OCI_URL" ]] || warn "No OCI HelmRepository found automatically — set it via the SRC_OCI env var."
SRC_OCI="${SRC_OCI:-$KCM_OCI_URL}"
[[ -n "$SRC_OCI" ]] || die "Could not determine the kcm chart OCI source. Set SRC_OCI=oci://..."

log "Pulling $SRC_CHART:$SRC_CHART_VERSION from $SRC_OCI ..."
rm -f "$SRC_CHART"-*.tgz
helm pull "${SRC_OCI%/}/${SRC_CHART}" --version "$SRC_CHART_VERSION" \
  || die "helm pull failed — the source may need auth; see runbook for the Flux-artifact fallback."
rm -rf "$SRC_CHART"
tar xzf "${SRC_CHART}-${SRC_CHART_VERSION}.tgz"

# ---------------------------------------------------------------------------
# 2. Edit exactly two fields: k0s.version (the fix) and Chart.version (avoid collision)
# ---------------------------------------------------------------------------
log "Pinning k0s.version -> $FIXED_K0S_VERSION (was $(yq '.k0s.version' "$SRC_CHART/values.yaml"))"
yq -i ".k0s.version = \"$FIXED_K0S_VERSION\"" "$SRC_CHART/values.yaml"

log "Bumping chart version $SRC_CHART_VERSION -> $NEW_CHART_VERSION (annotations preserved)"
yq -i ".version = \"$NEW_CHART_VERSION\"" "$SRC_CHART/Chart.yaml"
# Keep appVersion (cosmetic; surfaced in ClusterTemplate .status.version) in sync
# with the real hosted-CP k0s version we pin in values.k0s.version above.
yq -i ".appVersion = \"$FIXED_K0S_VERSION\"" "$SRC_CHART/Chart.yaml"

# Verify the 4 CAPI provider annotations survived (required for ClusterDeployment-time validation)
yq '.annotations' "$SRC_CHART/Chart.yaml" | grep -q 'cluster.x-k8s.io' \
  || die "cluster.x-k8s.io provider annotations missing after edit — aborting"
ok "Chart forked. k0s=$(yq '.k0s.version' "$SRC_CHART/values.yaml"), version=$(yq '.version' "$SRC_CHART/Chart.yaml")"

helm package "$SRC_CHART" -d "$WORKDIR" >/dev/null
PKG="${WORKDIR}/${SRC_CHART}-${NEW_CHART_VERSION}.tgz"
[[ -f "$PKG" ]] || die "helm package did not produce $PKG"

# ---------------------------------------------------------------------------
# 3. Publish as an HTTP Helm repo in a DEDICATED (non-tfstate) S3 bucket
# ---------------------------------------------------------------------------
if ! aws s3api head-bucket --bucket "$CHART_BUCKET" 2>/dev/null; then
  log "Creating chart bucket $CHART_BUCKET ..."
  if [[ "$AWS_REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$CHART_BUCKET" --region "$AWS_REGION" >/dev/null
  else
    aws s3api create-bucket --bucket "$CHART_BUCKET" --region "$AWS_REGION" \
      --create-bucket-configuration LocationConstraint="$AWS_REGION" >/dev/null
  fi
  # Public read for the chart objects only (chart is a non-sensitive open template copy).
  aws s3api put-public-access-block --bucket "$CHART_BUCKET" \
    --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false" >/dev/null
  aws s3api put-bucket-policy --bucket "$CHART_BUCKET" --policy "{
    \"Version\":\"2012-10-17\",
    \"Statement\":[{\"Sid\":\"PublicReadCharts\",\"Effect\":\"Allow\",\"Principal\":\"*\",
      \"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::${CHART_BUCKET}/*\"}]}" >/dev/null
  aws s3 website "s3://${CHART_BUCKET}/" --index-document index.yaml >/dev/null
fi

REPO_URL="https://${CHART_BUCKET}.s3.${AWS_REGION}.amazonaws.com"
log "Uploading chart + index to $REPO_URL ..."
aws s3 cp "$PKG" "s3://${CHART_BUCKET}/" >/dev/null
# Merge into an index (download existing first so re-runs accumulate)
aws s3 cp "s3://${CHART_BUCKET}/index.yaml" "$WORKDIR/index.yaml" 2>/dev/null || true
if [[ -f "$WORKDIR/index.yaml" ]]; then
  helm repo index "$WORKDIR" --url "$REPO_URL" --merge "$WORKDIR/index.yaml"
else
  helm repo index "$WORKDIR" --url "$REPO_URL"
fi
aws s3 cp "$WORKDIR/index.yaml" "s3://${CHART_BUCKET}/index.yaml" >/dev/null
ok "Forked chart published."

# ---------------------------------------------------------------------------
# 4. Register the Flux HelmRepository + ClusterTemplate
# ---------------------------------------------------------------------------
log "Applying HelmRepository/$HELMREPO_NAME and ClusterTemplate/$NEW_TEMPLATE_NAME in $NS ..."
cat <<YAML | kubectl apply -f -
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: ${HELMREPO_NAME}
  namespace: ${NS}
  labels:
    k0rdent.mirantis.com/managed: "true"
spec:
  interval: 1m
  url: ${REPO_URL}
---
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterTemplate
metadata:
  name: ${NEW_TEMPLATE_NAME}
  namespace: ${NS}
spec:
  helm:
    chartSpec:
      chart: ${SRC_CHART}
      version: ${NEW_CHART_VERSION}
      sourceRef:
        kind: HelmRepository
        name: ${HELMREPO_NAME}
YAML

log "Waiting for ClusterTemplate/$NEW_TEMPLATE_NAME to become valid ..."
kubectl wait --for=jsonpath='{.status.valid}'=true \
  clustertemplate/"$NEW_TEMPLATE_NAME" -n "$NS" --timeout=180s \
  || die "Template not valid. Inspect: kubectl get clustertemplate $NEW_TEMPLATE_NAME -n $NS -o jsonpath='{.status.validationError}'"

ok "ClusterTemplate '$NEW_TEMPLATE_NAME' is valid and ready."
echo
echo "Use it in your ClusterDeployment:    spec.template: ${NEW_TEMPLATE_NAME}"
echo "Bundled hosted-CP k0s version:       ${FIXED_K0S_VERSION}  (k0s #7832 fixed)"
