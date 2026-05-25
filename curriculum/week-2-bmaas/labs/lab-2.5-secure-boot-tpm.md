# Lab 2.5 — Hardware Root of Trust, Secure Boot, and TPM 2.0

| Domain | Tag | NVIDIA Req IDs |
|--------|-----|----------------|
| BMaaS / Security / Firmware | 🟢 NCP | SEC22, CNP09 |

> **Compliance pack artifact targets:** `artifacts/SEC22-secure-boot-attestation.md`, `artifacts/SEC22-tpm-quote-sample.bin`, `artifacts/CNP09-firmware-inventory.json`

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| BMaaS / Security | Required (NCP track) | 2 hours |

| Previous | Current | Next |
|----------|---------|------|
| [Lab 2.4 — BMC Hardening](lab-2.4-bmc-hardening.md) | **Lab 2.5 — Secure Boot + TPM 2.0** | [Week 3 — VMaaS](../../week-3-vmaas/README.md) |

```
Week 2 BMaaS path:
   2.1 image build → 2.2 discovery → 2.3 troubleshooting → 2.4 BMC hardening → [2.5 Secure Boot + TPM] → Week 3
```

---

**Duration:** 2 hours
**Type:** Theory-heavy + targeted hands-on
**Environment:** Bare-metal host with TPM 2.0 and UEFI Secure Boot capability, BMC accessible via Redfish (real or sushy-tools simulation — but TPM steps require real hardware or a libtpms-based simulator such as `swtpm`)

## Table of Contents

- [Why this lab exists](#why-this-lab-exists)
- [Learning Objectives](#learning-objectives)
- [Prerequisites](#prerequisites)
- [Architectural Decision Frame](#architectural-decision-frame)
- [Part 1: The chain of trust](#part-1-the-chain-of-trust)
- [Part 2: UEFI Secure Boot keys (PK, KEK, db, dbx)](#part-2-uefi-secure-boot-keys-pk-kek-db-dbx)
- [Part 3: TPM 2.0 fundamentals](#part-3-tpm-20-fundamentals)
- [Part 4: Hands-on — verify Secure Boot, read PCRs, capture a quote](#part-4-hands-on--verify-secure-boot-read-pcrs-capture-a-quote)
- [Part 5: CNP09 firmware attestation](#part-5-cnp09-firmware-attestation)
- [Part 6: Producing the compliance-pack artifacts](#part-6-producing-the-compliance-pack-artifacts)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [Next Lab](#next-lab)

---

## Why this lab exists

The v2.3 guide states two requirements that this lab covers end-to-end:

- **SEC22** — *"Mandatory support across all platforms for Hardware Root of Trust mechanisms (TPM 2.0). The platform must enable UEFI OS Secure Boot w/ TPM 2.0."*
- **CNP09** — *"Between tenants, all firmware must be brought to a known good state, all firmware must be cryptographically signed and attested during boot."*

This curriculum is otherwise relentlessly hands-on, but this lab is intentionally theory-heavy. Secure Boot, Measured Boot, TPM PCR extension, and firmware attestation are a stack of cryptographic guarantees that engineers commonly hand-wave away. The Mirantis annotations flag SEC22 with an open question — *"Do all nodes need TPM 2.0 as a hard requirement?"* — meaning engineers delivering NCP infrastructure will be asked to justify the posture. To do that they need the threat model and the chain of trust, not just commands. Theory first, hands-on second.

---

## Learning Objectives

By completing this lab, you will be able to:

- [ ] Define **Root of Trust** and explain why it must be immutable and on-die
- [ ] Distinguish **Secure Boot** (enforcement) from **Measured Boot** (recording) and explain why both are needed
- [ ] Diagram the UEFI Secure Boot key hierarchy (PK → KEK → db/dbx) and explain who controls each
- [ ] Explain TPM 2.0 PCR extension: why you can extend a PCR but never set it directly
- [ ] Capture and verify a TPM quote with `tpm2_quote` and `tpm2_checkquote`, including nonce handling
- [ ] Inventory and attest the firmware of every signed component on a node (BIOS, BMC, NIC, GPU VBIOS, NVSwitch tray)
- [ ] Articulate the tradeoff in the Mirantis open question about TPM 2.0 as a hard requirement
- [ ] Produce the SEC22 and CNP09 compliance-pack artifacts

---

## Prerequisites

- Lab 2.2 (BMC discovery) — required, for Redfish familiarity
- Lab 2.4 (BMC hardening) — required, for the BMC TLS posture the Redfish calls in this lab assume
- Basic familiarity with public-key cryptography (key pairs, signatures, hashes) — if you can explain why `sha256(message || key)` is not a valid signature, you're fine
- `tpm2-tools` ≥ 5.x installed on the test host (`apt install tpm2-tools` on Debian/Ubuntu, `dnf install tpm2-tools` on RHEL-likes)
- `mokutil`, `efibootmgr`, `curl`, `jq`, `openssl`
- For simulation: `swtpm` (libtpms wrapper) — only required if you don't have a hardware TPM available

---

## Architectural Decision Frame

| Choice | Option A | Option B | Recommendation |
|--------|----------|----------|----------------|
| TPM 2.0 as a hard requirement | Mandatory on every node — refuse to enroll without it | Strong preference — allow legacy nodes with compensating controls (signed PXE chain + offline attestation) | **Mandatory for new fleet; strong preference with documented exception process for legacy.** See Mirantis open-question discussion below — the v2.3 wording says "mandatory" but reality is uneven. Pick mandatory and write down the exception path. |
| Secure Boot key enrollment | Replace OEM PK/KEK with NCP-controlled keys (full custody) | Append NCP KEK alongside OEM KEK, keep OEM PK | **Append NCP KEK, keep OEM PK** — full PK replacement breaks vendor firmware-update tooling on many platforms (fwupd capsules, OEM utilities). Appending an NCP KEK lets you control db/dbx for tenant boot artifacts while still receiving signed firmware updates. |
| Attestation cadence | Boot-only quote (capture once at first boot per tenant) | Periodic re-attestation (every N hours, or on demand) | **Boot-only quote per tenant boot + on-demand re-quote API.** Periodic attestation costs runtime cycles and doesn't catch much that boot-time doesn't; on-demand re-quote covers incident response. |
| Firmware update workflow | Signed UEFI capsule via `fwupd` (LVFS-aligned) | Vendor tooling only (Dell DSU, HPE SUM, Supermicro SUM) | **`fwupd` where the vendor publishes to LVFS; vendor tooling otherwise.** `fwupd` (github.com/fwupd/fwupd) gives you a uniform CLI + signature verification across the fleet; for vendors that don't publish to LVFS (still common in BMC/NIC space), you fall back to vendor tooling and wrap it in a controller. |

### The Mirantis open question — should TPM 2.0 be hard-required?

The v2.3 guide says "mandatory." Mirantis annotated this with: *"Do all nodes need TPM 2.0 as a hard requirement?"* This is a real architectural question.

**Pros of mandatory (the v2.3 wording):** a node without a TPM cannot produce a quote, so it cannot satisfy CNP09 "attested during boot" — there is no substitute. An attacker who replaces firmware on a non-TPM node will never be detected by attestation. Hardware in scope for NCP today (DGX, OEM HGX) all ships with TPM 2.0 — the mandate has zero cost on greenfield.

**Pros of strong-preference with exception process:** brownfield nodes (lab gear, evaluation systems, older inventory) may lack a functional TPM, and a hard mandate blocks any phased migration. "Mandatory" without an exception process leads engineers to silently disable verification rather than block delivery — worse outcome. Compensating controls *can* close most of the gap: signed PXE chain + immutable boot disk + out-of-band firmware inventory snapshots.

**Recommendation in this curriculum:** mandatory for any node entering the production NCP fleet, with an explicit per-node, time-bounded, compensating-control exception process for documented brownfield cases. Don't let exceptions become permanent by accident.

---

## Part 1: The chain of trust

A chain of trust is only as strong as its weakest link, and only meaningful if the *first* link is immutable. From bottom to top:

```
┌───────────────────────────────────────────────────────────────────────────┐
│ Layer                  Measured into PCR    Signature checked by          │
├───────────────────────────────────────────────────────────────────────────┤
│ Boot ROM (on-die)      —  (the root)        —  (it IS the root)           │
│ ME / PSP firmware      PCR 0 (via SRTM)     Boot ROM (vendor key fused)   │
│ UEFI firmware          PCR 0, 1             ME/PSP                        │
│ Option ROMs (NIC,GPU)  PCR 2                UEFI (db keys)                │
│ Boot loader (shim,grub)PCR 4                UEFI Secure Boot db           │
│ Kernel + initramfs     PCR 4, 9             shim/grub (MOK or db)         │
│ Userspace policy       PCR 8, 10 (IMA)      Kernel IMA keyring            │
└───────────────────────────────────────────────────────────────────────────┘
```

Two distinct mechanisms operate at every step:

- **Secure Boot (enforcement):** the loader refuses to execute the next stage if its signature does not chain to a key in the platform's `db` (or MOK list for the shim case). *Prevents* unsigned code from running.
- **Measured Boot (recording):** the current stage hashes the next stage and *extends* that hash into a TPM PCR. *Records* what was actually loaded, signed or not, for later remote inspection.

You need both. Secure Boot without Measured Boot means a compromised db boots silently. Measured Boot without Secure Boot means you record the compromise faithfully but never stopped it. The combination is the posture SEC22 requires.

**Why the boot ROM must be on-die and immutable:** if an attacker can rewrite the first link, every signature above it is paperwork — they re-sign with their key, the chain reports green all the way up. On-die ROM plus fuses for the root key make the first link physically immutable.

---

## Part 2: UEFI Secure Boot keys (PK, KEK, db, dbx)

UEFI Secure Boot uses a four-tier key hierarchy stored in NVRAM:

| Variable | Cardinality | Who controls it | What it does |
|----------|-------------|-----------------|--------------|
| **PK** (Platform Key) | Exactly one | Platform owner | Authorizes changes to KEK. Holds the keys to the kingdom. |
| **KEK** (Key Exchange Keys) | One or more | Platform owner + delegated authorities (Microsoft, vendor, NCP) | Authorizes changes to db and dbx |
| **db** (allowed signatures) | Many entries | KEK holders | Signatures of permitted boot artifacts (shim, bootloader, kernel modules) |
| **dbx** (forbidden signatures) | Many entries | KEK holders | Revocation list — wins over db |

The signing flow: a bootloader binary has its hash signed by some key K. UEFI checks that K's certificate appears in `db` (and not in `dbx`). If yes, the binary may run; if no, refusal.

### Custody decisions

OEM ships hardware with PK=OEM, KEK=OEM+Microsoft, db=Microsoft UEFI CA + OEM driver signing, dbx=the published UEFI revocations (refer to the dbx published by the UEFI Forum).

Three choices for an NCP fleet:

1. **Leave OEM keys in place** — easiest, trusts the Microsoft chain and OEM driver signing. Acceptable for shared infrastructure; weaker isolation than NCP requirements imply.
2. **Append NCP KEK** — keep OEM PK, add your KEK alongside Microsoft's. You can now manage your own db/dbx entries for tenant boot artifacts without breaking OEM firmware updates. **Recommended posture.**
3. **Full custody (replace PK, KEK, db)** — strongest isolation, breaks most OEM firmware-update workflows. Only choose this if you own the entire firmware-update lifecycle and will sign every capsule yourself.

### Enrollment via Redfish

Modern BMCs expose Secure Boot key management under `/redfish/v1/Systems/{id}/SecureBoot` and `/redfish/v1/Systems/{id}/SecureBootDatabases` (DMTF Redfish schema). Read current state:

```bash
curl -ks -u root:... \
  https://10.99.0.10/redfish/v1/Systems/System.Embedded.1/SecureBoot \
  | jq '{ SecureBootEnable, SecureBootCurrentBoot, SecureBootMode }'
# Expected in production: SecureBootEnable=true, SecureBootMode="DeployedMode"
```

`DeployedMode` is the production posture — `SetupMode` accepts a new PK without authentication (fine for first enrollment, never left enabled). Enroll an NCP-owned KEK (exact action URI varies by vendor):

```bash
curl -k -u root:... -X POST \
  https://10.99.0.10/redfish/v1/Systems/System.Embedded.1/SecureBootDatabases/KEK/Certificates \
  -H 'Content-Type: application/json' -d @ncp-kek.json
```

`ncp-kek.json` carries the PEM/DER of the NCP-owned KEK certificate. Confirm with a GET on the same collection.

---

## Part 3: TPM 2.0 fundamentals

### What a TPM is

A TPM 2.0 is a small cryptographic coprocessor (discrete chip, firmware-TPM, or virtual via swtpm) that generates and stores keys that never leave the chip in plaintext, maintains **PCRs** (Platform Configuration Registers — append-only hash accumulators), signs structured statements about its internal state ("quotes") with an attestation key, and seals/unseals secrets to PCR values.

### PCRs and the extension operation

A PCR is a fixed-size register (32 bytes for SHA-256). You cannot write to it. The only operation is `Extend`:

```
PCR_new = HASH(PCR_old || measurement)
```

Two properties: **order matters** (A then B differs from B then A — boot order is baked into the result), and **you cannot reach a desired PCR value without knowing the exact sequence of measurements** (a successful boot chain reproduces a known-good set; any deviation produces a different value).

PCRs are organized into **banks** by hash algorithm. SHA-1 and SHA-256 banks both exist on TPM 2.0 hardware. **Use SHA-256.** SHA-1 is deprecated and present only for legacy compatibility — never base attestation policy on SHA-1 PCRs.

Standard PCR allocations (PC Client Platform Firmware Profile):

| PCR | Records |
|-----|---------|
| 0 | UEFI firmware code (SRTM) |
| 1 | UEFI firmware configuration / setup data |
| 2 | UEFI driver/option-ROM code (NIC, GPU) |
| 3 | UEFI driver/option-ROM configuration |
| 4 | Boot loader code |
| 5 | Boot loader configuration / GPT |
| 7 | Secure Boot policy (PK, KEK, db, dbx contents) |
| 8 | grub commands / kernel command line (varies) |
| 9 | initramfs / kernel modules (via shim/grub) |
| 10 | Linux IMA log |

### Quotes — the cryptographic statement

A **quote** is the TPM saying: "at this moment, with this nonce you provided, the PCRs you asked about have these values, signed by this attestation key whose public part you already know." Quote contents (TPMS_ATTEST) include a magic value, the verifier-supplied nonce, the selected PCR values, the signing key reference, and a signature over all of it.

**Why the nonce matters:** without a fresh nonce, an attacker could replay a known-good quote from a non-compromised boot. The verifier supplies a random nonce, the TPM includes it in the signed payload, the verifier confirms it on receipt. Old quotes are useless against new nonces.

The signing key is typically an **Attestation Key (AK)**, derived from the TPM's primary seed and certified by an **Endorsement Key (EK)** whose certificate the TPM vendor publishes. The EK certificate is the anchor — it ties this physical TPM (and therefore this physical machine) to the quote.

---

## Part 4: Hands-on — verify Secure Boot, read PCRs, capture a quote

All commands below are real `tpm2-tools` 5.x invocations against a real TPM (or `swtpm` if simulating).

### 4.1 — Verify Secure Boot is on

From the OS, then from the BMC (out-of-band, source of truth):

```bash
# OS view
mokutil --sb-state                              # Expected: "SecureBoot enabled"
od -An -t x1 /sys/firmware/efi/efivars/SecureBoot-* | head -1   # Last byte: 01

# BMC view (Redfish)
curl -ks -u root:... \
  https://10.99.0.10/redfish/v1/Systems/System.Embedded.1/SecureBoot \
  | jq '{ SecureBootEnable, SecureBootMode, SecureBootCurrentBoot }'
```

Both views must agree. If OS says enabled but Redfish says disabled, either the kernel is lying or the BMC is stale — both are findings.

### 4.2 — Read PCRs

```bash
# Read the SHA-256 bank for PCRs 0-10
tpm2_pcrread sha256:0,1,2,3,4,5,7,8,9,10

# Output format:
#   sha256:
#     0 : 0xC5B5...
#     1 : 0x9F3A...
#     ...
```

Snapshot these values for a known-good boot. They become the **reference PCR set** for attestation policy.

### 4.3 — Create an Attestation Key

```bash
# Endorsement primary key (deterministic from EK seed)
tpm2_createek -c ek.ctx -G rsa -u ek.pub

# Attestation Key under the EK hierarchy
tpm2_createak -C ek.ctx -c ak.ctx -G rsa -g sha256 -s rsassa -u ak.pub -n ak.name
```

`ak.pub` is published to the verifier; `ak.ctx` is the local handle the next command uses.

### 4.4 — Capture a quote

```bash
# Fresh nonce (the verifier supplies this in production; generated locally here)
openssl rand -hex 20 > nonce.hex
NONCE=$(cat nonce.hex)

# Quote PCRs 0,1,2,3,4,5,7 in the SHA-256 bank
tpm2_quote -c ak.ctx -l sha256:0,1,2,3,4,5,7 -q $NONCE \
  -m quote.msg -s quote.sig -o quote.pcrs -g sha256
```

Outputs: `quote.msg` (TPMS_ATTEST blob), `quote.sig` (signature), `quote.pcrs` (PCR values referenced in the quote).

### 4.5 — Verify the quote

```bash
tpm2_checkquote \
  -u ak.pub \
  -m quote.msg \
  -s quote.sig \
  -f quote.pcrs \
  -g sha256 \
  -q $NONCE

# Exit code 0 means: signature valid, nonce matches, PCR digest matches.
```

Three things just got proven: (1) the quote came from the TPM holding the private half of `ak.pub` (signature verified); (2) it was generated freshly in response to *this* nonce (replay defeated); (3) the PCR values are exactly as recorded in `quote.pcrs` (boot state captured).

What you still need to do *outside* the TPM: compare `quote.pcrs` against your **reference PCR set** for this hardware + boot configuration. The TPM cannot tell you whether the PCRs are "good" — only that they are what they are. The policy decision is yours.

---

## Part 5: CNP09 firmware attestation

CNP09: *"all firmware must be cryptographically signed and attested during boot."*

"Firmware" on an HGX/DGX-class node means more than the host BIOS. Every signed component needs an inventory entry, a known-good version, and a verification step:

| Component | Inventory source | Signature verification |
|-----------|------------------|------------------------|
| Host BIOS / UEFI | Redfish `/Systems/{id}` `BiosVersion`, `/Systems/{id}/Bios` | UEFI Secure Boot db (covered in Part 2) |
| BMC firmware | Redfish `/Managers/{id}` `FirmwareVersion` | Vendor signing chain (Dell, HPE, Supermicro all publish signed BMC firmware) |
| NIC firmware (ConnectX, BlueField) | `mlxfwmanager --query` or Redfish `/NetworkAdapters/{id}/Firmware` | NVIDIA-published firmware signatures (NIC vendor key) |
| GPU VBIOS | `nvidia-smi -q | grep "VBIOS Version"` or Redfish `/Systems/{id}/Processors/GPU{n}` | NVIDIA VBIOS signing chain |
| NVSwitch tray firmware | NVIDIA fabric manager / Redfish accelerator subtree | NVIDIA NVSwitch signing chain |
| PSU, drive controller, etc. | Redfish `/Chassis/{id}/Power` and `/Storage/{id}/Controllers` | Vendor-specific |

### Inventory collection

```bash
# Collect a per-component firmware inventory via Redfish
curl -ks -u root:... \
  https://10.99.0.10/redfish/v1/UpdateService/FirmwareInventory \
  | jq '.Members[]."@odata.id"' \
  | xargs -n1 -I{} curl -ks -u root:... "https://10.99.0.10{}" \
  | jq -s 'map({ id: .Id, name: .Name, version: .Version, signed: .Oem.Signed // null, updateable: .Updateable })'
```

This produces the structured inventory CNP09 expects: every component, its version, whether it's signed, whether it's updateable.

### Bringing firmware to a known-good state between tenants

CNP09 also requires that *between* tenants, firmware is reset to known-good. The workflow:

1. Tenant releases the node (Lab 6.4 covers crypto-erase for data; CNP09 covers firmware).
2. Inventory current firmware vs. known-good baseline.
3. For any deviation, re-flash via signed images. Prefer `fwupd` for components published to LVFS:
   ```bash
   fwupdmgr refresh
   fwupdmgr get-devices
   fwupdmgr install <firmware-cab-file>      # signed cabinet file, verified by fwupd
   ```
4. For components without LVFS coverage (most BMC/NIC firmware today), use vendor tooling wrapped in a controller that verifies the vendor signature against the published key, logs the version transition, and fails closed if verification fails.
5. Re-capture a TPM quote post-reflash and compare PCRs to baseline.

### Fail-closed posture

If *any* in-scope firmware component is unsigned or its signature cannot be verified, the node must not enter the tenant fleet. Document the exception process (signed approval, time-bounded, compensating controls) for components where the vendor has not yet implemented signing — and treat each such exception as a debt to be retired.

---

## Part 6: Producing the compliance-pack artifacts

```bash
# 1. Secure Boot + TPM attestation summary (assembled into Markdown)
{
  echo "# SEC22 — Secure Boot + TPM 2.0 Attestation"
  echo "## Node: $STABLE_ID"
  echo "### Secure Boot (per BMC, source of truth)"
  curl -ks -u root:... https://10.99.0.10/redfish/v1/Systems/System.Embedded.1/SecureBoot \
    | jq '{ SecureBootEnable, SecureBootMode, SecureBootCurrentBoot }'
  echo "### Secure Boot (per OS)"; mokutil --sb-state
  echo "### TPM 2.0 presence"; tpm2_getcap properties-fixed | grep -E 'TPM2_PT_(MANUFACTURER|FIRMWARE_VERSION|VENDOR)'
  echo "### Reference PCR set (SHA-256, post known-good boot)"
  tpm2_pcrread sha256:0,1,2,3,4,5,7
  echo "### Attestation"
  echo "- AK pub sha256: $(sha256sum ak.pub | awk '{print $1}')"
  echo "- Latest quote: SEC22-tpm-quote-sample.bin"
  echo "- Nonce: $NONCE"
  echo "- tpm2_checkquote exit 0 at $(date -u +%FT%TZ)"
} > SEC22-secure-boot-attestation.md

# 2. TPM quote sample (binary) — TPMS_ATTEST + signature + PCR snapshot
tar cf SEC22-tpm-quote-sample.bin quote.msg quote.sig quote.pcrs nonce.hex ak.pub

# 3. CNP09 firmware inventory
curl -ks -u root:... \
  https://10.99.0.10/redfish/v1/UpdateService/FirmwareInventory \
  | jq '.Members[]."@odata.id"' \
  | xargs -n1 -I{} curl -ks -u root:... "https://10.99.0.10{}" \
  | jq -s '{
      node_ref: "'"$STABLE_ID"'",
      captured_at: "'"$(date -u +%FT%TZ)"'",
      components: map({ id: .Id, name: .Name, version: .Version,
                        updateable: .Updateable,
                        signed: (.Oem.Signed // null),
                        signature_verified: null })
    }' > CNP09-firmware-inventory.json

# Fill in `signature_verified` per component via a follow-up controller pass
# that runs vendor verification tooling — recorded so an auditor can see
# what was checked vs. accepted on faith.
```

Each artifact filename starts with its Req ID so the compliance pack can sort and discover them automatically.

---

## Verification Checklist

- [ ] `mokutil --sb-state` reports "SecureBoot enabled" and Redfish `SecureBootEnable` is `true` — both views agree
- [ ] Redfish `SecureBootMode` is `DeployedMode` (not `SetupMode`)
- [ ] NCP-owned KEK is present in `/SecureBootDatabases/KEK/Certificates` (if append-mode chosen) or NCP-owned PK is enrolled (if full-custody chosen)
- [ ] `tpm2_getcap properties-fixed` shows `TPM2_PT_FAMILY_INDICATOR` is `2.0`
- [ ] Reference PCR set captured for known-good boot (SHA-256 bank, PCRs 0–10) and stored in the compliance pack
- [ ] `tpm2_checkquote` returns exit 0 against a fresh quote with a fresh nonce
- [ ] CNP09 firmware inventory enumerates BIOS, BMC, every NIC, every GPU VBIOS, every NVSwitch tray (where present)
- [ ] Every inventory entry has either a verified signature or a documented, time-bounded exception
- [ ] `fail-closed` posture verified — a node with an unsigned in-scope component cannot enter the tenant fleet
- [ ] Artifacts SEC22 (attestation summary + quote bytes) and CNP09 (firmware inventory) produced and Req-ID-stamped

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `mokutil --sb-state` says disabled but you enabled Secure Boot in firmware | Boot order is hitting a non-Secure-Boot path (legacy CSM, USB rescue) | Disable CSM/legacy boot in firmware; confirm boot entry uses the signed `\EFI\BOOT\BOOTX64.EFI` path |
| TPM owner password lost or unknown | Provisioning didn't clear ownership before deployment | Clear the TPM via firmware setup (physical presence required on most platforms) and re-provision; owner-clear wipes all keys, so plan re-attestation |
| PCRs 0/1/2 change unexpectedly between boots | Firmware update, microcode update, or option-ROM change in the boot path | Investigate `BiosVersion` / firmware inventory drift first; re-baseline reference PCRs only after confirming the change is expected and signed |
| PCR 4 changes after a kernel update | Expected — shim/grub measure the loaded bootloader and kernel | Update the reference PCR set when you intentionally update the kernel; treat unexplained PCR 4 deltas as incidents |
| Vendor does not sign their firmware (most often: older NIC or BMC builds) | Vendor lags on the CNP09 signing requirement | File a vendor escalation, document the exception with compensating controls, set a deadline; do not silently accept |
| `fwupd` refuses to flash with "signature verification failed" | Either the cab file is genuinely unsigned/tampered, or the LVFS keyring on the host is out of date | `fwupdmgr refresh` to update keyring; if still failing, do not bypass — verify the cab signature manually with `gpg --verify` against the vendor's published key |

---

## Key Takeaways

- **Root of Trust must be immutable and on-die.** Everything above it is paperwork if the root can be rewritten.
- **Secure Boot and Measured Boot are different mechanisms — you need both.** Secure Boot enforces; Measured Boot records. A quote without enforcement records a compromise; enforcement without recording hides one.
- **You cannot fake a TPM quote.** The nonce defeats replay; the signature ties the quote to a specific physical TPM whose EK certificate is anchored to the vendor. But the TPM is not a policy engine — *you* compare PCR values against a reference set.
- **CNP09 is a fleet-wide inventory problem, not just a BIOS-signature problem.** BMC, NIC, GPU VBIOS, NVSwitch tray all count. Build the inventory once, run it on every node lifecycle transition.
- **The Mirantis open question about TPM 2.0 has a real answer:** mandatory for new fleet, with a documented exception process for legacy. Do not let "strong preference" become "silently disabled."

---

## Next Lab

[Week 3 — VMaaS](../../week-3-vmaas/README.md). With the BMC locked down (Lab 2.4) and the boot chain attested (Lab 2.5), the bare-metal layer is ready to host virtualization for tenant workloads. Week 3 builds the VM substrate on top of this foundation.
