# Per-Student Lab Infrastructure Design

**Date:** 2026-02-20
**Status:** Approved
**Author:** AI-assisted design session

## Problem

The current two-step shared infrastructure model causes deployment failures for students:

1. A global `shared` environment (VPC, bastion, S3, IAM) must be deployed before any per-student environment.
2. Per-student environments (`k0rdent`, `gpu-lab`, `metal3-dev`, `kubevirt-lab`) read shared outputs via `terraform_remote_state`.
3. `check_shared_infrastructure()` uses VPC tag existence as a proxy for Terraform state availability — these can be out of sync.
4. A single S3 tfstate bucket is shared across all students and regions, requiring `BUCKET_REGION` tracking and cross-region detection.

**Failure mode:** When the VPC exists (from another student or prior run) but the Terraform state is at a different S3 key than expected, `public_subnet_ids` evaluates to `null` and the deploy fails with `Missing required argument`.

## Solution

Replace the global shared + per-student environment model with a single per-student Terraform root that contains everything: networking, bastion, IAM, k0rdent cluster, and optional secondary lab environments.

## Architecture

### Before (two-step, shared state)

```
S3 bucket (script) -> shared env (terraform) -> k0rdent env (terraform)
                           ^                         ^
                     terraform_remote_state     terraform_remote_state
                           ^                         ^
                     gpu/metal3/kubevirt also read shared state
```

### After (one-step, per student)

```
Per-student S3 bucket (script) -> student-lab env (single terraform apply)
                                  contains: networking + bastion + IAM
                                          + k0rdent cluster
                                          + [optional: gpu/metal3/kubevirt]
```

## S3 Bucket Strategy

**Per-student bucket:**
- Name: `k0rdent-lab-{engineer_id}-{account_id}`
- Region: same as student's `--region` flag
- State key: `terraform.tfstate` (flat, single key)

Created by the provisioning script before `terraform init`. Eliminates:
- `BUCKET_REGION` tracking
- `get_bucket_region()` detection
- Cross-region S3 backend configuration
- `migrate_legacy_state_keys()`

## Terraform Structure

### New environment: `environments/student-lab/`

Single root module that composes existing modules:

```hcl
module "networking" {
  source = "../../modules/networking"
  project_name = var.project_name
  engineer_id  = var.engineer_id
  vpc_cidr     = var.vpc_cidr
  ...
}

module "bastion" {
  source    = "../../modules/bastion"
  subnet_id = module.networking.public_subnet_ids[0]
  ...
}

module "iam" {
  source      = "../../modules/iam"
  engineer_id = var.engineer_id
  ...
}

module "k0rdent_mgmt" {
  source            = "../../modules/k0rdent-mgmt"
  vpc_id            = module.networking.vpc_id
  subnet_id         = module.networking.private_subnet_ids[0]
  public_subnet_ids = module.networking.public_subnet_ids
  bastion_sg_id     = module.networking.bastion_sg_id
  ...
}

module "gpu_lab" {
  count  = var.enable_gpu_lab ? 1 : 0
  source = "../../modules/gpu-lab"
  ...
}

module "metal3_dev" {
  count  = var.enable_metal3 ? 1 : 0
  source = "../../modules/metal3-dev"
  ...
}

module "kubevirt_lab" {
  count  = var.enable_kubevirt ? 1 : 0
  source = "../../modules/kubevirt-lab"
  ...
}
```

### New modules (extracted from shared-infra)

1. **`modules/networking/`** — VPC, subnets (public, private, GPU), NAT gateway, IGW, route tables, security groups. Resource names include `engineer_id` to avoid collisions between students.

2. **`modules/iam/`** — IAM roles (lab-instance, lab-provisioner, lab-admin), policies, instance profiles. Names include `engineer_id`.

### Modified modules

3. **`modules/k0rdent-mgmt/`** — Remove `aws.s3` provider alias (no cross-region S3). S3 objects for SSH keys and k0sctl config go to the student's bucket in their region.

4. **`modules/bastion/`** — No changes needed (already self-contained). Resource names updated to include `engineer_id`.

5. **`modules/gpu-lab/`**, **`modules/metal3-dev/`**, **`modules/kubevirt-lab/`** — No internal changes. Wired to networking module outputs instead of `terraform_remote_state`.

### Deleted directories

- `environments/shared/` — replaced by inline modules
- `environments/k0rdent/` — replaced by `environments/student-lab/`
- `environments/gpu-lab/` — absorbed into `student-lab` via feature flag
- `environments/metal3-dev/` — absorbed into `student-lab` via feature flag
- `environments/kubevirt-lab/` — absorbed into `student-lab` via feature flag
- `modules/shared-infra/` — split into `modules/networking/` + `modules/iam/`

## Script Changes

### `lab-provision.sh`

Eliminates ~200 lines of shared infrastructure detection and migration logic:

- `check_shared_infrastructure()` — deleted
- `ensure_shared_infrastructure()` — deleted
- `migrate_legacy_state_keys()` — deleted
- `get_bucket_region()` — deleted
- `BUCKET_REGION` variable — deleted
- `provision_shared()` — deleted
- `provision_k0rdent()`, `provision_metal3()`, etc. — merged into single `provision_lab()`
- `ensure_s3_buckets()` — simplified (per-student bucket)

New flow:
```bash
provision_lab() {
    local engineer_id="$1"
    local bucket="k0rdent-lab-${engineer_id}-${ACCOUNT_ID}"

    ensure_student_bucket "$bucket"

    cd "$TERRAFORM_DIR/environments/student-lab"
    terraform init -reconfigure \
        -backend-config="bucket=${bucket}" \
        -backend-config="key=terraform.tfstate" \
        -backend-config="region=${REGION}"

    terraform apply $apply_args \
        -var="engineer_id=${engineer_id}" \
        -var="region=${REGION}" \
        -var="enable_gpu_lab=${ENABLE_GPU}" \
        -var="enable_metal3=${ENABLE_METAL3}" \
        -var="enable_kubevirt=${ENABLE_KUBEVIRT}"
}
```

### `lab-connect.sh`

- `get_bastion_ip()` reads from student's state (same bucket) instead of shared state
- `get_bucket_region()` eliminated — bucket is always in student's region
- State key paths simplified: no region prefix needed

### `lab-destroy.sh`

- Single `terraform destroy` tears down everything
- `destroy_shared()` eliminated (no shared infra)
- `destroy_all_engineer()` simplified — one destroy command
- Per-student S3 bucket optionally deleted on full teardown

### `lab-status.sh`

- `show_shared_status()` eliminated
- All status queries read from single student state file

## Cost Impact

Per student, per 8-hour session:
| Resource | Monthly | Per session (8h) |
|----------|---------|-----------------|
| NAT Gateway | $32 | $0.50 |
| Bastion (t3.micro) | $8 | $0.09 |
| Elastic IP | $3.65 | $0.03 |
| **Networking overhead** | **$43.65** | **$0.62** |

k0rdent cluster cost unchanged (t3.xlarge: ~$1.33/session).

Total overhead vs shared model: +$0.62/session per student. Negligible for training use.

## Migration

Students with active deployments must destroy and re-provision. Training labs have 8-hour TTL — no state migration needed. Old S3 bucket and state files can be cleaned up manually or left to expire.

## What This Eliminates

| Removed Component | Lines Removed (est.) |
|---|---|
| `terraform_remote_state` data sources | ~40 lines across 4 environments |
| `check_shared_infrastructure()` | ~15 lines |
| `ensure_shared_infrastructure()` | ~35 lines |
| `migrate_legacy_state_keys()` | ~40 lines |
| `get_bucket_region()` / `BUCKET_REGION` | ~30 lines across 4 scripts |
| `provision_shared()` | ~60 lines |
| `destroy_shared()` | ~20 lines |
| `show_shared_status()` | ~30 lines |
| `environments/shared/` directory | ~120 lines (3 files) |
| **Total removed** | **~390 lines** |
