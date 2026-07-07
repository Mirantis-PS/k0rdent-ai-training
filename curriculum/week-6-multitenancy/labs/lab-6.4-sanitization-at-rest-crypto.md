# Lab 6.4 — Data Sanitization + At-Rest Encryption

**Domain:** Multi-Tenancy / Security / Lifecycle

> **Standards reference:** NIST SP 800-88 rev1 — *Guidelines for Media Sanitization* (Clear / Purge / Destroy taxonomy). Throughout this lab, "crypto-erase" maps to **Purge** in 800-88 terms; "overwrite" maps to **Clear**.

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Multi-Tenancy / Security | Required | 2.5 hours |

| Previous | Current | Next |
|----------|---------|------|
| [Lab 6.3 — Capacity & Fleet APIs](lab-6.3-capacity-fleet-apis.md) | **Lab 6.4 — Sanitization + At-Rest Crypto** | (Lab 6.5 — OIDC Federation — TBD) |

```
Tenant N releases node
         │
         ▼
   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
   │ Host drives  │  │ GPU memory   │  │ etcd/secrets │  │ TPM + BIOS   │
   │  (SED CE)    │  │ (HBM scrub)  │  │ (key rotate) │  │  (clear)     │
   └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
          └─────────────────┴─────────────────┴─────────────────┘
                                    │
                                    ▼
                       Evidence YAML → Audit trail
                                    │
                                    ▼
                       Node returns to pool (Tenant N+1)
```

---

**Duration:** 2.5 hours
**Type:** Design + Hands-on
**Environment:** k0rdent management cluster + at least one tenant cluster with bare-metal nodes (or simulated BMH); access to a GPU node for memory wipe steps

## Table of Contents

- [Why this lab exists](#why-this-lab-exists)
- [Learning Objectives](#learning-objectives)
- [Prerequisites](#prerequisites)
- [Architectural Decision Frame](#architectural-decision-frame)
- [Part 1: The four data locations](#part-1-the-four-data-locations)
- [Part 2: SED crypto-erase of host drives](#part-2-sed-crypto-erase-of-host-drives)
- [Part 3: GPU memory wipe — HBM, SRAM, caches](#part-3-gpu-memory-wipe--hbm-sram-caches)
- [Part 4: etcd + secrets encryption at rest](#part-4-etcd--secrets-encryption-at-rest)
- [Part 5: TPM + BIOS reset](#part-5-tpm--bios-reset)
- [Part 6: Wiring sanitization into the Breakfix lifecycle](#part-6-wiring-sanitization-into-the-breakfix-lifecycle)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [Next Lab](#next-lab)

---

## Why this lab exists

What "tenancy ends" means operationally: the next tenant on the same hardware must not be able to recover any data from the previous tenant. The standard requirements that any serious multi-tenant operator commits to:

- All data drives between tenants must be **cryptographically erased**.
- All persistent and volatile memory, including SRAM and GPU memory, must be **sanitized/wiped**.
- The **TPM and BIOS shall be reset** before the host returns to the available pool.
- All host drives must support **at-rest encryption via Self-Encrypted Drives (SED)**.
- Drive sanitization must come with **full attestation of host firmware** so a compromised drive firmware can't simply log without erasing.

Engineers commonly read this as "wipe the disks." It is wider than that. Tenant data lands in **four** classes of storage on a GPU node, and all four must be sanitized before the node returns to the pool:

| # | Location | Examples | Persistence |
|---|----------|----------|-------------|
| 1 | **Host drives** | NVMe data drives, local SATA SSDs | Persistent |
| 2 | **Accelerator memory** | HBM3/HBM3e on GPU, on-die SRAM, NVSwitch buffers | Volatile (residual after power-off ≠ zero) |
| 3 | **Cluster state** | etcd database, Kubernetes Secrets, controller caches on disk | Persistent |
| 4 | **Platform state** | TPM PCRs / NV indices, BIOS NVRAM (boot order, secrets, KEK slots) | Persistent |

Operationally, "tenancy ends" is the union of: SED crypto-erase (1), HBM/SRAM scrub (2), encryption-key rotation (3), and platform reset (4) — **each with attestable evidence**. This lab covers all four and wires them into the Breakfix lifecycle from Lab 6.2 so sanitization is not a manual checklist a human might skip.

---

## Learning Objectives

By completing this lab, you will be able to:

- [ ] State the four data locations that require sanitization between tenants and the mechanism for each
- [ ] Verify a drive is SED-capable and perform a cryptographic erase (NIST 800-88 Purge) with attestation
- [ ] Explain why `nvidia-smi --gpu-reset` does not wipe HBM, and run the correct GPU-memory sanitization sequence
- [ ] Configure etcd encryption-at-rest with `aescbc` (or KMS) and rotate the data-encryption key
- [ ] Reset TPM and BIOS state via tpm2-tools and Redfish, and capture a firmware-version attestation
- [ ] Extend the `BreakfixRequest` CRD with a `sanitization` phase that gates re-provisioning
- [ ] Produce verifiable evidence (operator, timestamp, drive serial, sanitize-status, firmware-signature) for each step

---

## Prerequisites

- **Lab 6.2 (Breakfix API)** — required. Sanitization is a phase in the breakfix lifecycle; this lab extends the CRD from 6.2.
- **Lab 2.4 (BMC Hardening)** — required. Redfish-over-TLS is the transport for BIOS reset and firmware attestation.
- **Lab 2.5 (Secure Boot / TPM)** — recommended. You will be clearing the TPM you provisioned there.
- **Signed-firmware attestation pipeline** (see Lab 2.5) — referenced; SED firmware trust depends on it.
- Tools: `sg_inq`, `hdparm`, `nvme-cli`, `nvidia-smi`, `tpm2-tools`, `curl`, `kubectl`, `jq`, `yq`.

---

## Architectural Decision Frame

| Choice | Option A | Option B | Recommendation |
|--------|----------|----------|----------------|
| Drive sanitization method | NIST 800-88 **Clear** (full overwrite, hours per drive) | NIST 800-88 **Purge** (SED cryptographic erase, seconds) | **Purge via SED crypto-erase** — only viable approach at fleet scale; mandated by SEC20 anyway |
| Tenant isolation on drive | Single tenant per drive (whole-drive ownership) | Cryptographic isolation per tenant (one DEK per tenant on a shared drive) | **Single tenant per drive** for v1; per-tenant DEK on shared drives only when key custody can be proven separable from the drive firmware |
| etcd encryption provider | `aescbc` (k8s-native, local key) | `kms` v2 (external KMS, e.g., Vault Transit) | **`aescbc` for the first compliance pass, `kms` v2 for production** — KMS removes the local-key custody problem and centralizes rotation |
| Kubernetes secret protection | k8s-native encrypted secrets only | + Sealed Secrets / External Secrets Operator (ESO) | **k8s-native + ESO** — never store plaintext secrets in Git; ESO pulls from Vault/cloud KMS at runtime |
| Sanitization automation | Manual runbook executed by operator | Integrated into `BreakfixRequest` CRD as a required step | **Integrated CRD step** — manual runbooks are how "the GPU was reset but HBM wasn't scrubbed" tickets happen |

---

## Part 1: The four data locations

Mapping each location to its required action and evidence:

| # | Location | Sanitization mechanism | NIST 800-88 class | Evidence captured |
|---|----------|------------------------|-------------------|-------------------|
| 1 | NVMe / SATA data drives (SED) | `nvme sanitize` (crypto-erase) or `sg_format --cmplst` | **Purge** | Drive serial, sanitize action ID, completion timestamp, operator |
| 2 | GPU HBM + on-die SRAM | Drain → idle dwell → ECC scrub → optional fill-pattern → power-cycle | **Purge** (vendor-specific) | GPU UUID, scrub start/end ts, ECC counter delta, operator |
| 3 | etcd DB + k8s Secrets | DEK rotation + namespace secret re-encryption | N/A (key-rotation, not media) | DEK ID before/after, rotation ts, KMS audit log line |
| 4 | TPM + BIOS NVRAM | `tpm2_clear`, Redfish BIOS factory reset, firmware re-attest | **Purge** | TPM clear ts, PCR0 post-reset, BIOS version, firmware signature (Lab 2.5) |

Two observations anchor the rest of the lab:

1. **A single non-SED drive in the chassis voids the SED guarantee for the node.** Discover this *before* the breakfix moment.
2. **`nvidia-smi --gpu-reset` is not a sanitization primitive.** It re-initializes the GPU control path; it does not guarantee HBM contents are scrubbed. See Part 3.

---

## Part 2: SED crypto-erase of host drives

### 2.1 Verify drives are SED-capable

For each data drive on the node, before any tenant ever touches it:

```bash
# SATA / SAS — look for "Encryption" / "TCG Opal" support
sudo hdparm -I /dev/sda | grep -E 'Security|Encryption|Trusted'
sudo sg_inq -p sai /dev/sda                           # SCSI inquiry, supplemental info
sudo sedutil-cli --query /dev/sda                     # TCG Opal feature set

# NVMe — sanitize capabilities live in the controller identify page
sudo nvme id-ctrl /dev/nvme0 -H | grep -E 'sanicap|Sanitize'
# Expected: SANICAP bits indicating crypto erase (CES) and/or block erase (BES) supported
```

A drive is acceptable when TCG Opal 2 is supported **and** the PSID is recorded in asset inventory, or when NVMe SANICAP indicates `Crypto Erase Supported = 1`. Drives failing both checks are flagged "non-SED, requires 800-88 Clear" — a slow path you don't want to discover at 02:00 on an RMA.

### 2.2 SED firmware trust — pair with firmware attestation

> SED crypto-erase is only as trustworthy as the firmware running it. Compromised drive firmware could log-without-erasing the DEK, or refuse the sanitize while reporting success.

The control here is firmware signing + attestation (see Lab 2.5). Before the drive's first tenant assignment, and before each crypto-erase event, capture:

```bash
sudo nvme fw-log /dev/nvme0                           # firmware history slots
sudo nvme id-ctrl /dev/nvme0 | grep -E 'fr|sn|mn'     # firmware rev, serial, model
```

Compare to the vendor's signed-firmware manifest (Lab 2.5). Mismatch = fail closed: drive does not return to the pool until re-flashed from a signed image.

### 2.3 Perform the cryptographic erase

NVMe path (preferred — fastest, fully in-drive):

```bash
# action=4 = Crypto Erase. action=2 = Block Erase (fallback).
sudo nvme sanitize /dev/nvme0 --sanact=4 --ause=0

# Poll status until SSTAT.STATUS = "Sanitize Operation Completed Successfully"
while true; do
  STATUS=$(sudo nvme sanitize-log /dev/nvme0 -H | awk -F: '/Sanitize Status/ {print $2}')
  echo "$(date -u +%FT%TZ) status=$STATUS"
  echo "$STATUS" | grep -q "Completed Successfully" && break
  sleep 5
done
```

SATA/SAS (Opal SED) path:

```bash
# Issue a TCG Revert via PSID — burns the DEK, full crypto-erase
sudo sedutil-cli --yesIreallywanttoERASEALLmydatainTHISDRIVE \
    PSID <PSID-FROM-DRIVE-LABEL> /dev/sda

# Verify: drive should report no Opal locking ranges configured
sudo sedutil-cli --query /dev/sda | grep -E 'Locked|LockingEnabled'
```

### 2.4 Capture attestation

For every sanitize event, emit a record (this becomes evidence YAML in Part 7):

```yaml
event: drive-sanitize
drive:
  device: /dev/nvme0
  serial: BTLJ123456789-A
  model:  Micron 7450 MAX
  firmware: E2010600
sanitize:
  method: nvme-crypto-erase           # nvme-crypto-erase | nvme-block-erase | tcg-revert | overwrite-800-88-clear
  nist_800_88_class: Purge
  started_at: 2026-05-25T14:02:10Z
  completed_at: 2026-05-25T14:02:14Z
  status: Completed Successfully
operator: bf-controller@k0rdent       # human or controller identity
breakfix_request: bf-gpu-node-01-replace
firmware_attestation_ref: cnp09-att-2026-05-25-001
```

One record per drive per sanitize. Never aggregate — the auditor wants per-serial evidence.

---

## Part 3: GPU memory wipe — HBM, SRAM, caches

### 3.1 What `nvidia-smi --gpu-reset` actually does

`nvidia-smi --gpu-reset` issues a secondary-bus-level reset and re-initializes the GPU. It is sufficient for recovering a hung GPU. **It does not guarantee HBM contents are cleared:**

- HBM is only deterministically zeroed by an explicit driver write or specific firmware-init paths not promised by the `--gpu-reset` contract.
- HBM3/HBM3e holds charge for tens of ms to seconds after power loss; SRAM caches longer under cold conditions.
- A reset does not power-cycle the HBM stack — data remanence is plausible.

SEC21 calls out SRAM and GPU memory explicitly. The answer is *not* `--gpu-reset`.

### 3.2 The correct sequence

```bash
NODE=gpu-node-01
GPU_UUID=$(nvidia-smi --query-gpu=uuid --format=csv,noheader | head -n1)

# 1. Drain workloads — no processes referencing the GPU
kubectl cordon "$NODE"
kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data --force --grace-period=120
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv   # expect empty

# 2. Detach from NVLink fabric (per Lab 6.2 Part 5)
nvidia-fabric-manager-cli detach --gpu "$GPU_UUID"

# 3. Idle dwell — let on-chip caches and HBM refresh paths flush
sleep 60

# 4. Full ECC scrub. Disable then re-enable ECC; re-enable triggers a full HBM scrub on driver init.
ECC_BEFORE=$(nvidia-smi --id="$GPU_UUID" \
  --query-gpu=ecc.errors.uncorrected.aggregate.total --format=csv,noheader,nounits)
sudo nvidia-smi --id="$GPU_UUID" -e 0 && sudo nvidia-smi --id="$GPU_UUID" -r
sudo nvidia-smi --id="$GPU_UUID" -e 1 && sudo nvidia-smi --id="$GPU_UUID" -r
ECC_AFTER=$(nvidia-smi --id="$GPU_UUID" \
  --query-gpu=ecc.errors.uncorrected.aggregate.total --format=csv,noheader,nounits)

# 5. (Optional, paranoid) Explicit CUDA fill — write a known constant across all HBM, then zero.
/opt/nvidia-tools/hbm-fill --gpu "$GPU_UUID" --pattern 0xA5 --then-zero

# 6. Power-cycle the node via BMC so HBM loses charge fully
curl -k -u "$BMC_USER:$BMC_PASS" -X POST \
  "https://$BMC_HOST/redfish/v1/Systems/1/Actions/ComputerSystem.Reset" \
  -d '{"ResetType":"ForceOff"}'
sleep 30
curl -k -u "$BMC_USER:$BMC_PASS" -X POST \
  "https://$BMC_HOST/redfish/v1/Systems/1/Actions/ComputerSystem.Reset" \
  -d '{"ResetType":"On"}'
```

### 3.3 Evidence

```yaml
event: gpu-memory-sanitize
gpu:
  uuid: GPU-1a2b3c4d-...
  model: B200
  vbios: 92.00.45.00.05
sanitize:
  steps: [drain, fm-detach, dwell, ecc-cycle, fill-pattern, power-cycle]
  ecc_uncorrected_before: 0
  ecc_uncorrected_after:  0
  dwell_seconds: 60
  started_at:   2026-05-25T14:05:00Z
  completed_at: 2026-05-25T14:13:00Z
operator: bf-controller@k0rdent
breakfix_request: bf-gpu-node-01-replace
```

The fill-pattern step is optional under SEC21 ("sanitized/wiped", not "overwritten with a known pattern") but makes evidence unambiguous and costs minutes per GPU. Include it for sensitivity-class-3+ tenants.

---

## Part 4: etcd + secrets encryption at rest

### 4.1 Why this is sanitization-adjacent

A tenant cluster's etcd holds tenant Secrets: pull-creds, SA tokens, application secrets. When tenancy ends:

1. Rotate the DEK protecting those Secrets — any residual etcd snapshot on backup media now decrypts with a key that no longer exists.
2. Delete the Secret objects (confirm no controllers cached them on disk outside etcd).

K8S19 ("encryption at rest for etcd and secrets") is the mechanism; key rotation is how it serves SEC21.

### 4.2 Configure encryption at rest (k0s example)

```yaml
# /etc/kubernetes/encryption-config.yaml — referenced by --encryption-provider-config
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
      - configmaps                       # optional; recommend on for production
    providers:
      - aescbc:
          keys:
            - name: key-2026-05         # current (write) key
              secret: <BASE64-32-BYTES>
            - name: key-2026-02         # previous key, still decryptable
              secret: <BASE64-32-BYTES>
      - identity: {}                     # fallback for un-migrated entries
```

For k0s, reference this in the controller config:

```yaml
spec:
  api:
    extraArgs:
      encryption-provider-config: /etc/kubernetes/encryption-config.yaml
```

For production (recommended), switch the first provider to `kms` v2 backed by Vault Transit / AWS KMS / GCP KMS so the DEK never lives on the API server's disk.

### 4.3 Rotate the DEK between tenants

```bash
# 1. Generate a new key
NEW_KEY=$(head -c 32 /dev/urandom | base64)
NEW_NAME="key-$(date -u +%Y-%m-%d)"

# 2. Prepend new key to providers (it becomes the write key, old keys stay for decrypt)
yq -i ".resources[0].providers[0].aescbc.keys = \
  [{\"name\":\"$NEW_NAME\",\"secret\":\"$NEW_KEY\"}] + .resources[0].providers[0].aescbc.keys" \
  /etc/kubernetes/encryption-config.yaml

# 3. Restart kube-apiserver(s) so the new key is loaded as the write key
sudo systemctl restart k0scontroller

# 4. Re-encrypt all secrets with the new write key
kubectl get secrets --all-namespaces -o json \
  | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' \
  | while read ns name; do
      kubectl get secret "$name" -n "$ns" -o json \
        | kubectl replace -f -
    done

# 5. Validate — read raw from etcd, expect "k8s:enc:aescbc:v1:$NEW_NAME:"
sudo ETCDCTL_API=3 etcdctl \
  --cacert=/var/lib/k0s/pki/etcd/ca.crt \
  --cert=/var/lib/k0s/pki/apiserver-etcd-client.crt \
  --key=/var/lib/k0s/pki/apiserver-etcd-client.key \
  get /registry/secrets/default/<a-secret-name> | hexdump -C | head
# Expected prefix: k8s:enc:aescbc:v1:key-2026-05:
```

### 4.4 Retire the old DEK

Once all of tenant N's secrets are re-encrypted under the new key **and** all old-key etcd snapshots are crypto-erased from backup media, remove the old key from `encryption-config.yaml` and restart the API server. Any leaked snapshot is now permanently undecryptable.

---

## Part 5: TPM + BIOS reset

### 5.1 Clear the TPM

```bash
# Check current state
sudo tpm2_getcap properties-variable | grep -E 'ownerAuthSet|lockoutAuthSet|TPM2_PT_PERMANENT'
sudo tpm2_pcrread sha256:0,1,2,3,4,5,6,7

# Clear with platform/lockout auth
sudo tpm2_clear -c platform
# or, if platform hierarchy is unavailable:
sudo tpm2_clear -c lockout
```

> **Physical-presence note.** Some platforms require physical-presence to clear the TPM, usually exposed via Redfish as `Oem.TpmClear` or a BIOS attribute. If `tpm2_clear` returns `TPM_RC_AUTHORIZATION` / `TPM_RC_DISABLED`, drive it via BMC — see 5.2.

### 5.2 BIOS factory-reset + firmware attestation via Redfish

```bash
BMC="https://$BMC_HOST"
AUTH=(-u "$BMC_USER:$BMC_PASS" -k)

# 1. Capture firmware versions BEFORE (attestation evidence)
curl "${AUTH[@]}" "$BMC/redfish/v1/UpdateService/FirmwareInventory" \
  | jq '.Members[].["@odata.id"]' \
  | xargs -I{} curl "${AUTH[@]}" "$BMC{}" \
  | jq '{id:.Id, ver:.Version, sig:.Oem.SignatureStatus}' > firmware-pre-reset.json

# 2. Reset BIOS to defaults; optionally clear TPM via Redfish (some platforms)
curl "${AUTH[@]}" -X POST "$BMC/redfish/v1/Systems/1/Bios/Actions/Bios.ResetBios"
curl "${AUTH[@]}" -X POST "$BMC/redfish/v1/Managers/1/Actions/Oem/TpmClear"   # if supported

# 3. Power-cycle so the BIOS reset takes effect
curl "${AUTH[@]}" -X POST "$BMC/redfish/v1/Systems/1/Actions/ComputerSystem.Reset" \
  -d '{"ResetType":"ForceRestart"}'

# 4. Re-collect post-reset and diff for the attestation log
# ... same FirmwareInventory query > firmware-post-reset.json
diff firmware-pre-reset.json firmware-post-reset.json
```

### 5.3 Evidence

```yaml
event: platform-reset
tpm:
  cleared_at: 2026-05-25T14:20:00Z
  pcr0_post: 0000000000000000000000000000000000000000000000000000000000000000
  method: tpm2_clear -c platform
bios:
  reset_at: 2026-05-25T14:22:00Z
  version: 1.6.2
  firmware_attestation_ref: cnp09-att-2026-05-25-002
operator: bf-controller@k0rdent
breakfix_request: bf-gpu-node-01-replace
```

---

## Part 6: Wiring sanitization into the Breakfix lifecycle

The point is that sanitization is a controller-enforced phase between drain and re-provision — not a five-page runbook. Humans miss steps; controllers don't. Extend the `BreakfixRequest` CRD from Lab 6.2:

```yaml
apiVersion: ops.k0rdent.mirantis.com/v1alpha1
kind: BreakfixRequest
metadata:
  name: bf-gpu-node-01-replace
spec:
  target:
    nodeName: gpu-node-01
    nodeRef:
      uid: nvr-7f2a-9c3b-2e8a
  action: replace
  reason: "Tenant release"
  initiator: dgxc-bot@dgxc.nvidia.com
  sanitization:                            # NEW — gates re-provisioning
    required: true
    profile: sec21-full                    # sec21-full | sec21-drives-only | none
    drives:
      method: nvme-crypto-erase            # fallback: overwrite-800-88-clear
    gpuMemory:
      method: ecc-cycle-plus-power-cycle
      fillPattern: false                   # set true for sensitivity-class-3+
    cluster:
      rotateEncryptionKey: true
    platform:
      clearTpm: true
      resetBios: true
      attestFirmware: true                  # ties to firmware-signing pipeline (Lab 2.5)
status:
  phase: Sanitizing                         # Pending|InProgress|Sanitizing|Completed|Failed
  steps:
    - { name: cordon,                status: Succeeded }
    - { name: drain,                 status: Succeeded }
    - { name: nvlink-domain-detach,  status: Succeeded }
    - { name: sanitize-drives,       status: Succeeded, evidenceRef: ev-drives-001 }
    - { name: sanitize-gpu-memory,   status: Succeeded, evidenceRef: ev-gpu-001 }
    - { name: rotate-etcd-dek,       status: Succeeded, evidenceRef: ev-etcd-001 }
    - { name: clear-tpm,             status: Succeeded, evidenceRef: ev-tpm-001 }
    - { name: reset-bios,            status: Succeeded, evidenceRef: ev-bios-001 }
    - { name: attest-firmware,       status: Succeeded, evidenceRef: ev-cnp09-001 }
    - { name: bmh-deprovision,       status: InProgress }
```

Controller rules:

- `bmh-deprovision` **must not start** until every sanitization step is `Succeeded` (or explicitly waived via `spec.sanitization.profile=none` — RBAC-gated, audit-annotated).
- Each `evidenceRef` points to a `SanitizationEvidence` CR with the per-step YAML from Parts 2-5.
- Refuse `replace` if any non-SED drive is present and `drives.method = nvme-crypto-erase` (fail closed).
- Refuse `replace` if firmware attestation fails after BIOS reset.

This is what makes SEC21 enforceable rather than aspirational.

---

## Part 7: Produce the compliance-pack artifacts

### Artifact 1 — `SEC21-sanitization-runbook.md`

Human-readable end-to-end procedure mirroring the controller flow in Part 6: four-locations table from Part 1, commands from Parts 2-5 as the authoritative reference, the "non-SED fallback" decision tree, and sample evidence YAMLs.

### Artifact 2 — `SEC21-evidence-template.yaml`

```yaml
apiVersion: compliance.k0rdent.mirantis.com/v1alpha1
kind: SanitizationEvidence
metadata:
  name: ev-<breakfix>-<step>
spec:
  breakfixRequest: <name>
  node: { nodeRef: <uid>, serial: <chassis-serial> }
  events:
    - event: drive-sanitize
      drive: { device: /dev/nvme0, serial: ..., model: ..., firmware: ... }
      sanitize: { method: nvme-crypto-erase, nist_800_88_class: Purge,
                  started_at: <ISO8601>, completed_at: <ISO8601>, status: Completed Successfully }
      operator: bf-controller@k0rdent
      firmware_attestation_ref: <cnp09-id>
    - event: gpu-memory-sanitize
      gpu: { uuid: ..., model: B200, vbios: ... }
      sanitize: { steps: [drain, fm-detach, dwell, ecc-cycle, power-cycle],
                  ecc_uncorrected_before: 0, ecc_uncorrected_after: 0,
                  started_at: <ISO8601>, completed_at: <ISO8601> }
      operator: bf-controller@k0rdent
    - event: etcd-dek-rotate
      dek_before: key-2026-02
      dek_after:  key-2026-05
      rotated_at: <ISO8601>
      kms_audit_ref: <kms-event-id>
    - event: platform-reset
      tpm:  { cleared_at: <ISO8601>, pcr0_post: 0x000..., method: tpm2_clear -c platform }
      bios: { reset_at: <ISO8601>, version: 1.6.2, firmware_attestation_ref: <cnp09-id> }
status:
  phase: Closed
  sealed_at: <ISO8601>
  hash: sha256:<digest>           # tamper-evident hash of the events block
```

### Artifact 3 — `SEC20-sed-attestation.md`

Per-node table: every drive, with serial, model, firmware rev, SED capability (TCG Opal / NVMe SANICAP), PSID stored location, and a reference to the signed-firmware attestation (Lab 2.5). Generated by the same DaemonSet that powers the diagnostics surface in Lab 6.2.

### Artifact 4 — `K8S19-etcd-encryption-config.yaml`

Snapshot of the `EncryptionConfiguration` from Part 4 with key material redacted (`secret:` → `[REDACTED]`, names retained). Paired with a key-rotation history log:

```yaml
rotations:
  - key: key-2026-02
    created: 2026-02-01T00:00:00Z
    retired: 2026-05-25T14:30:00Z
    retired_reason: tenant-release-bf-gpu-node-01-replace
  - key: key-2026-05
    created: 2026-05-25T14:25:00Z
    retired: null
```

Generate and stage:

```bash
mkdir -p artifacts
cp docs/sanitization-runbook.md          artifacts/SEC21-sanitization-runbook.md
cp templates/sanitization-evidence.yaml  artifacts/SEC21-evidence-template.yaml
./scripts/gen-sed-attestation.sh         > artifacts/SEC20-sed-attestation.md
kubectl get cm -n kube-system encryption-config -o yaml \
  | yq '.data."encryption-config.yaml"' \
  | yq '.resources[].providers[].aescbc.keys[].secret = "[REDACTED]"' \
  > artifacts/K8S19-etcd-encryption-config.yaml
```

---

## Verification Checklist

- [ ] Every data drive in the chassis classified as SED-capable or flagged with an 800-88 Clear fallback path
- [ ] `nvme sanitize --sanact=4` (or TCG Revert) demonstrated end-to-end on a test drive, with per-serial evidence captured
- [ ] GPU memory sanitization sequence executed: drain → FM-detach → dwell → ECC cycle → power-cycle, with ECC counter delta = 0 captured
- [ ] etcd encryption-at-rest enabled with `aescbc` (or `kms` v2); raw etcd read shows `k8s:enc:aescbc:v1:<key-name>:` prefix
- [ ] DEK rotation procedure runs cleanly: new key prepended, all secrets re-encrypted, old key retired
- [ ] `tpm2_clear` succeeds and PCR0 reads as zeros post-reset
- [ ] Redfish `Bios.ResetBios` executed; firmware-inventory diff captured pre/post; signatures validated against the firmware-signing manifest
- [ ] `BreakfixRequest` CRD extended with the `sanitization` block; controller refuses `bmh-deprovision` until all steps `Succeeded`
- [ ] All four compliance-pack artifacts generated and staged under `artifacts/`
- [ ] Evidence YAML for at least one end-to-end run sealed (hash captured) and stored

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `nvme id-ctrl` shows SANICAP = 0 (no sanitize support) | Drive is non-SED, or firmware predates the sanitize command | Flag as non-SED in inventory; fall back to NIST 800-88 Clear (`nvme write-zeroes` across full LBA range, or `shred -v -n1 -z`) — slow but compliant. Plan to replace the drive. |
| GPU shows non-zero `ecc.errors.uncorrected.aggregate.total` after scrub | Genuine HBM error, or counter is sticky across the ECC disable/enable cycle | Power-cycle the node (not just the GPU) and re-read. Persistent non-zero = drive the GPU into RMA, not back to the pool. |
| etcd encryption rollout breaks API server start | Encryption config YAML malformed, or referenced key file missing | Validate with `kube-apiserver --encryption-provider-config=... --dry-run`-equivalent in a side container first; ensure the file is readable by the apiserver user; never edit live without a tested rollback. |
| `tpm2_clear` returns `TPM_RC_AUTHORIZATION` or `TPM_RC_DISABLED` | Platform requires physical-presence assertion; lockout auth set | Drive the clear via Redfish (`Oem.TpmClear`) or set a one-shot BIOS attribute (`TpmClearOnReboot=Enabled`) and reboot. Capture the BMC audit log line as evidence. |
| `nvme sanitize` returns `Invalid Field in Command` or "not supported" | Older drive firmware does not implement the Sanitize command set | Two paths: (a) upgrade drive firmware via the signed-firmware pipeline (Lab 2.5) and retry; (b) fall back to TCG Opal Revert via `sedutil-cli` if Opal is supported; (c) 800-88 Clear as last resort. |

---

## Key Takeaways

- **Sanitization is four problems, not one.** Drives, GPU memory, cluster state, and platform state each need their own mechanism and their own evidence.
- **`nvidia-smi --gpu-reset` is not HBM sanitization.** The correct sequence is drain → FM-detach → dwell → ECC cycle → power-cycle, with the ECC counter delta as the evidence.
- **SED crypto-erase is only as strong as the firmware running it.** Pair every sanitize with a firmware attestation (Lab 2.5) — without it, you are trusting the drive's word.
- **Encryption-at-rest is sanitization by another name.** Rotating the etcd DEK between tenants makes leaked backup snapshots cryptographically useless. Don't skip the retire step.
- **Make the controller refuse to skip steps.** A `BreakfixRequest` that re-provisions a node without `sanitization.status = Completed` is the bug class SEC21 exists to prevent.

---

## Next Lab

Lab 6.5 — OIDC Federation for tenant identity. Once a node has been sanitized and returned to the pool, the next concern is who, on the next tenant's side, is allowed to consume it — and how that identity is asserted across the trust boundary.
