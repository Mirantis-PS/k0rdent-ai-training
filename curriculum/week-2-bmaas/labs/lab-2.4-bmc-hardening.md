# Lab 2.4 — BMC Hardening for NCP

| Domain | Tag | NVIDIA Req IDs |
|--------|-----|----------------|
| BMaaS / Security | 🟢 NCP | SEC12 (BMC Security), CNP10 (Remote Management — Redfish over TLS, no IPMI), CNP06 (Console Access), CNP08 (Stable Identifiers) |

> **Compliance pack artifact targets:** `artifacts/SEC12-bmc-network-isolation.md`, `artifacts/CNP10-redfish-config-snapshot.json`, `artifacts/CNP06-console-retention-policy.md`

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| BMaaS / Security | Required (NCP track) | 1.5 hours |

| Previous | Current | Next |
|----------|---------|------|
| [Lab 2.3 — Troubleshooting BMC](lab-2.3-troubleshooting-bmc.md) | **Lab 2.4 — BMC Hardening** | (Lab 2.5 — Secure Boot + TPM — TBD) |

---

**Duration:** 1.5 hours
**Type:** Configuration + Verification
**Environment:** Metal3-managed BMC fleet (real or virtual via sushy-tools)

## Table of Contents

- [Why this lab exists](#why-this-lab-exists)
- [Learning Objectives](#learning-objectives)
- [Prerequisites](#prerequisites)
- [Architectural Decision Frame](#architectural-decision-frame)
- [Part 1: The BMC security posture NVIDIA expects](#part-1-the-bmc-security-posture-nvidia-expects)
- [Part 2: Network isolation — dedicated VLAN/VRF + jumphost](#part-2-network-isolation--dedicated-vlanvrf--jumphost)
- [Part 3: Disable IPMI, enforce Redfish over TLS](#part-3-disable-ipmi-enforce-redfish-over-tls)
- [Part 4: Stable identifiers (CNP08)](#part-4-stable-identifiers-cnp08)
- [Part 5: Serial console access + retention (CNP06)](#part-5-serial-console-access--retention-cnp06)
- [Part 6: Produce the compliance-pack artifacts](#part-6-produce-the-compliance-pack-artifacts)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [Next Lab](#next-lab)

---

## Why this lab exists

The v2.3 guide is unambiguous about BMC posture:

- **SEC12** — *"Out-of-band management (BMC) must be on a dedicated, restricted network (physically separate or VLAN/VRF-isolated). Direct access from the public internet or general corporate networks must be blocked, and only accessed via a hardened bastion (jumphost) server."*
- **CNP10** — *"Platform management solutions (e.g., BMC) must support Redfish over TLS (Disable IPMI)."*
- **CNP06** — *"Serial console access is required (read-only sufficient, interactive preferred). Serial console output shall be logged and be available for historic queries (at least 1 month retention)."*
- **CNP08** — *"All resources (e.g. nodes, switches) must have a stable and persistent ID that does not change during the lifespan."*

Lab 2.2 covered BMC discovery — the happy-path setup. This lab puts the security perimeter around it.

---

## Learning Objectives

By completing this lab, you will be able to:

- [ ] Diagram the BMC network isolation pattern (VLAN/VRF + jumphost)
- [ ] Configure Metal3 to talk to BMCs via Redfish-over-TLS with cert verification
- [ ] Disable IPMI on a representative BMC (where firmware supports it)
- [ ] Verify no IPMI ports are reachable from outside the BMC subnet
- [ ] Stamp a stable identifier onto every BareMetalHost that persists across re-provision
- [ ] Wire serial console output to a centralized log store with ≥30 day retention
- [ ] Produce the SEC12/CNP10/CNP06 compliance-pack artifacts

---

## Prerequisites

- Lab 2.2 (BMC discovery) — required
- Lab 1.7 (cert-manager) — required (you need an internal CA for BMC certs)
- Network admin access to the BMC management VLAN (or simulated equivalent)
- `kubectl`, `helm`, `redfish-client` (or `curl`), `openssl`, `nmap`

---

## Architectural Decision Frame

| Choice | Option A | Option B | Recommendation |
|--------|----------|----------|----------------|
| BMC network isolation | Dedicated physical NIC + switch | VLAN/VRF on shared switching | **VLAN + VRF** — physical is gold standard but cost-prohibitive; VRF gives equivalent isolation when properly implemented |
| Jumphost transport | SSH (line-mode) | mTLS-wrapped HTTPS proxy | **SSH with cert-based auth + session recording** — operators already know SSH; session recording satisfies audit |
| BMC certificate authority | Public CA | Internal CA (cert-manager) | **Internal CA** — BMC certs are short-lived per node; cert-manager rotates them; you don't want public-CA bills + privacy exposure |
| IPMI fallback | Allow on quarantined VLAN | Hard-disable | **Hard-disable where firmware supports it**, allow on quarantined VLAN otherwise — the v2.3 wording wants explicit disable |
| Stable ID source | BMC GUID | Custom NCP-issued UUID | **Custom UUID** — survives BMC firmware reset / motherboard swap where GUID may not |

---

## Part 1: The BMC security posture NVIDIA expects

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Internet / General Corp Net           BLOCKED                            │
└────────────────────────────┬────────────────────────────────────────────┘
                             │
                             ▼
                    ┌────────────────┐
                    │ Hardened       │  ← SSH + cert auth, session recording,
                    │ Jumphost       │     allowlist of source IPs
                    │ (bastion)      │
                    └───────┬────────┘
                            │
                            ▼
                ┌──────────────────────┐
                │  BMC Mgmt VLAN/VRF   │  ← no default route to Internet
                │  no IPMI ports       │     allowlist src/dst per node
                │  Redfish/TLS only    │
                └──┬────┬────┬────┬────┘
                   ▼    ▼    ▼    ▼
                  BMC  BMC  BMC  BMC
```

Three things must be simultaneously true:

1. **No path from the Internet / general corp net to the BMC subnet.** Verified with `nmap` from an outside host.
2. **Only the jumphost can reach BMCs.** Verified with ACL/firewall rules and a positive test from jumphost, negative test from outside.
3. **Only Redfish-over-TLS (port 443) reaches BMCs.** No 623/UDP (IPMI), no 80, no 5900 (VNC unless explicitly required).

---

## Part 2: Network isolation — dedicated VLAN/VRF + jumphost

Decision: VLAN with VRF.

Example switch config (Cisco IOS-XR or NX-OS; adapt to your vendor):

```text
! VRF for BMC management
vrf BMC-MGMT
  rd 65001:100
!
! Interface in VRF
interface Vlan 100
  vrf forwarding BMC-MGMT
  ip address 10.99.0.1 255.255.255.0
  no ip redirects
  no ip proxy-arp
!
! No route leak — leave BMC-MGMT isolated
```

Jumphost config (minimal Linux box):

- SSH only, key + cert (signed by internal CA, short TTL)
- Session recording (`tlog` or auditd + `script`)
- Firewall: inbound only from operator-VPN CIDR, outbound only to BMC-MGMT VLAN
- Hostname `bmc-jump-01`, immutable IP

Verify isolation:

```bash
# From a workstation NOT on the operator VPN
nmap -p 22,80,443,623 10.99.0.10
# Expected: all filtered or no response

# From operator VPN (allowed source)
ssh ops@bmc-jump-01
# Expected: succeeds

# From the jumphost
curl -kI https://10.99.0.10/redfish/v1/
# Expected: HTTPS handshake succeeds (TLS will be tightened in Part 3)
```

Document the diagram + ACL rules in `SEC12-bmc-network-isolation.md`.

---

## Part 3: Disable IPMI, enforce Redfish over TLS

On each BMC, disable IPMI services (vendor-specific). Examples:

```bash
# Dell iDRAC (via Redfish; pre-disable, you may need IPMI to send this last command if SSH/console is off)
curl -k -u root:CALVIN -X PATCH \
  https://10.99.0.10/redfish/v1/Managers/iDRAC.Embedded.1/NetworkProtocol \
  -H 'Content-Type: application/json' \
  -d '{"IPMI": {"ProtocolEnabled": false}}'

# Verify
curl -ks -u root:CALVIN https://10.99.0.10/redfish/v1/Managers/iDRAC.Embedded.1/NetworkProtocol \
  | jq '.IPMI.ProtocolEnabled'
# Expected: false
```

Issue BMC certificates via cert-manager. Pattern:

```yaml
# Certificate request per BMC (driven by a controller; example for one host)
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: bmc-10-99-0-10
  namespace: cert-manager
spec:
  secretName: bmc-10-99-0-10-tls
  issuerRef: { name: internal-ca, kind: ClusterIssuer }
  commonName: bmc-10-99-0-10.bmc.internal
  dnsNames:
    - bmc-10-99-0-10.bmc.internal
  ipAddresses:
    - 10.99.0.10
  duration: 2160h        # 90 days
  renewBefore: 360h      # 15 days
```

Push the cert to the BMC via Redfish:

```bash
curl -k -u root:CALVIN -X POST \
  https://10.99.0.10/redfish/v1/Managers/iDRAC.Embedded.1/Actions/Oem/EID_674_Manager.ImportSSLCertificate \
  -F 'Type=Server' -F 'SSLCertificate=@bmc-10-99-0-10.pem'
```

Update Metal3 `BMCSecret` to use TLS verification:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: bmc-credentials-node01
type: Opaque
data:
  username: ...
  password: ...
---
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node01
spec:
  bmc:
    address: redfish://10.99.0.10/redfish/v1/Systems/System.Embedded.1
    credentialsName: bmc-credentials-node01
    disableCertificateVerification: false   # explicit: enforce verification
  rootDeviceHints:
    deviceName: /dev/disk/by-path/pci-0000:c1:00.0-nvme-1
```

Verify cert verification is enforced by attempting a connection with the wrong CA — Metal3 should refuse to talk to the BMC.

---

## Part 4: Stable identifiers (CNP08)

Stable identifiers must persist across:

- BMC firmware reset
- Motherboard replacement (within the same chassis)
- Storage swap
- OS re-provision

Implementation: stamp a UUID generated by your NCP onto each chassis at first commissioning, store it in the `BareMetalHost` annotation, and project it onto:

- the chassis asset tag (via Redfish `PATCH /Chassis/{id}` `AssetTag`)
- the `Node` annotation `nvidia.com/node-ref` on every K8s provisioning
- the diagnostics output (Lab 6.2 BFX03)

```bash
# Generate stable ID once at commissioning
STABLE_ID="nvr-$(uuidgen | cut -c1-8)-$(uuidgen | cut -c1-4)-$(uuidgen | cut -c1-4)"
echo "$STABLE_ID"

# Stamp it on the chassis via Redfish
curl -k -u root:... -X PATCH \
  https://10.99.0.10/redfish/v1/Chassis/System.Embedded.1 \
  -H 'Content-Type: application/json' \
  -d "{\"AssetTag\": \"$STABLE_ID\"}"

# Stamp it on the BareMetalHost
kubectl annotate bmh node01 nvidia.com/node-ref=$STABLE_ID --overwrite
```

The CAP02 + CAP03 + BFX02 + BFX03 APIs all consume this ID. Don't reinvent it per surface.

---

## Part 5: Serial console access + retention (CNP06)

CNP06 requires:
- Serial console access (read-only OK, interactive preferred)
- Logged output
- At least 1 month retention

Wire BMC SOL (Serial-over-LAN) to a centralized collector:

```bash
# Per-node: enable SOL via Redfish
curl -k -u root:... -X PATCH \
  https://10.99.0.10/redfish/v1/Managers/iDRAC.Embedded.1/SerialInterfaces/Serial.1 \
  -H 'Content-Type: application/json' \
  -d '{"InterfaceEnabled": true, "ConnectorType": "RJ45"}'
```

Collect SOL via the jumphost, forward to OTel (Lab 5.17):

```bash
# Long-running connector that pipes SOL into syslog with the node's stable ID
ipmiconsole -h 10.99.0.10 -u sol -p ... 2>&1 \
  | logger -t bmc-sol -p local6.info --tag "bmc-sol node_ref=$STABLE_ID"
```

Retention: forward syslog (TLS) to the OTel Gateway from Lab 5.17; downstream OTLP receiver (DGXC or your own log store) must retain ≥30 days. Document the retention policy in `CNP06-console-retention-policy.md`.

---

## Part 6: Produce the compliance-pack artifacts

```bash
# 1. Network isolation diagram + ACL spec
cat > SEC12-bmc-network-isolation.md <<'EOF'
# BMC Network Isolation Posture
- VLAN 100, VRF BMC-MGMT, RD 65001:100
- No route leak
- Jumphost: bmc-jump-01, only inbound from operator-VPN CIDR (10.10.0.0/16)
- Outbound from BMCs: blocked
- nmap negative test from external host: <attach>
EOF

# 2. Redfish config snapshot per BMC
for bmc in $BMC_LIST; do
  curl -ks -u root:... https://$bmc/redfish/v1/Managers/iDRAC.Embedded.1/NetworkProtocol \
    | jq '{ host: "'"$bmc"'", IPMI: .IPMI, HTTPS: .HTTPS, SSH: .SSH, redfish_tls: .HTTPS.ProtocolEnabled }'
done | jq -s '.' > CNP10-redfish-config-snapshot.json

# 3. Console retention policy
cat > CNP06-console-retention-policy.md <<'EOF'
# Console Retention Policy
- All node SOL captured via BMC, tagged with node_ref (per CNP08)
- Forwarded via OTel (TLS) to DGXC-compatible log endpoint
- Retention: 35 days (5 days headroom over the v2.3 30-day minimum)
- Test query: `<example log query>` against the OTLP receiver
EOF
```

---

## Verification Checklist

- [ ] Negative `nmap` from outside operator VPN: all BMC ports filtered
- [ ] Positive Redfish from jumphost: TLS handshake succeeds with verified cert
- [ ] `IPMI.ProtocolEnabled == false` on every BMC where firmware supports
- [ ] Metal3 `disableCertificateVerification: false` on every BMH
- [ ] cert-manager renewing BMC certs ≥15 days before expiry
- [ ] Every `BareMetalHost` carries a `nvidia.com/node-ref` annotation matching the chassis AssetTag
- [ ] SOL traffic from every node reaching the central log store
- [ ] Log store retention ≥30 days, verified by sample query for >30-day-old data
- [ ] Artifacts SEC12, CNP10, CNP06 produced and Req-ID-stamped

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Metal3 fails with "x509 certificate signed by unknown authority" | Internal CA not trusted by the ironic pod | Mount the internal CA bundle into `ironic` and `ironic-inspector` pods |
| IPMI disable command returns 400 on some BMC firmware | Older firmware doesn't expose `IPMI.ProtocolEnabled` over Redfish | Use the OEM endpoint, or accept IPMI on quarantined VLAN with strict ACL until firmware upgrade |
| Asset tag reverts to "" after BMC firmware update | Vendor firmware reset clears AssetTag in some versions | Add a controller that re-stamps AssetTag on BMC inventory updates |
| SOL session drops every few minutes | TCP idle timeout on jumphost or switch | Set `ServerAliveInterval`/keepalive; document the long-running session as a known operational task |
| nmap from operator VPN times out | Jumphost is allowed but operator VPN itself is not | Verify the operator VPN CIDR is in the BMC subnet ACL allowlist |

---

## Key Takeaways

- **BMC is the highest-privilege surface in the stack.** Treat it like the gate to the kingdom, because it is.
- **Disabling IPMI is non-negotiable** where firmware supports it. Document exceptions, plan firmware upgrades.
- **Stable identifiers are infrastructure, not metadata.** Every NCP API surface (CAP02, BFX02/03, CNP02) consumes them — pick the scheme once and reuse everywhere.
- **The compliance-pack artifact for BMC posture is a packet capture + a config snapshot.** Both are easy to produce; both are what auditors actually read.

---

## Next Lab

Lab 2.5 — Secure Boot + TPM 2.0 (planned). Once the BMC is locked down, the next layer is making sure what boots on top is the firmware you signed.
