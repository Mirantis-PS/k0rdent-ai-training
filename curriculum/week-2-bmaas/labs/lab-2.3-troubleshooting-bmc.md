# Lab 2.3 - Troubleshooting BMC Connectivity

**Duration:** 2.5 hours
**Type:** Troubleshooting / Problem Solving

## Objective

Diagnose and resolve common BMC registration and connectivity failures that occur in production environments.

## Prerequisites

- Completed Lab 2.2
- Familiarity with Redfish API
- Lab environment with intentionally broken configurations

## Lab Environment

This lab uses scenarios with pre-configured failures. Each scenario simulates a real-world issue.

## Scenarios

### Scenario A: BMC Unreachable (45 min)

**Symptoms:**
```bash
$ curl -k -u admin:password https://192.168.111.10:8000/redfish/v1/
curl: (7) Failed to connect to 192.168.111.10 port 8000: Connection refused
```

**Investigation Steps:**

1. **Verify Network Path**
   ```bash
   # Check if IP is pingable
   ping -c 3 192.168.111.10

   # Check route exists
   ip route get 192.168.111.10

   # Check ARP table
   arp -n | grep 192.168.111
   ```

2. **Check Port Connectivity**
   ```bash
   # Test specific port
   nc -zv 192.168.111.10 8000

   # Or with timeout
   timeout 5 bash -c '</dev/tcp/192.168.111.10/8000' && echo "Open" || echo "Closed"
   ```

3. **Check Firewall Rules**
   ```bash
   # On management node
   iptables -L -n | grep -E "8000|REJECT|DROP"

   # Check if firewalld is blocking
   firewall-cmd --list-all
   ```

4. **Verify BMC Service Running**
   ```bash
   # If you have IPMI access as fallback
   ipmitool -I lanplus -H 192.168.111.10 -U admin -P password chassis status
   ```

**Resolution:**
Document the actual cause and fix applied:

```
Root Cause: _______________________
Fix Applied: _______________________
Verification: _______________________
```

---

### Scenario B: Authentication Failure (30 min)

**Symptoms:**
```bash
$ curl -k -u admin:password https://192.168.111.11:8000/redfish/v1/
{
  "error": {
    "code": "Base.1.0.GeneralError",
    "message": "Authentication failed"
  }
}
```
HTTP Status: 401 Unauthorized

**Investigation Steps:**

1. **Verify Credentials Format**
   ```bash
   # Test with explicit encoding
   curl -k -u "admin:password" -v https://192.168.111.11:8000/redfish/v1/

   # Check for special characters in password
   # If password has special chars, URL encode or use different quoting
   ```

2. **Check Account Status**
   ```bash
   # Some BMCs lock accounts after failed attempts
   # Try IPMI to check account status
   ipmitool -I lanplus -H 192.168.111.11 -U admin -P password user list
   ```

3. **Verify SSL/TLS Issues**
   ```bash
   # Check certificate details
   openssl s_client -connect 192.168.111.11:8000 -showcerts

   # Some BMCs have TLS version requirements
   curl -k --tlsv1.2 -u admin:password https://192.168.111.11:8000/redfish/v1/
   ```

4. **Test Alternative Credentials**
   ```bash
   # Try default credentials for vendor
   # Dell: root/calvin
   # HPE: Administrator/password
   # Supermicro: ADMIN/ADMIN
   ```

**Resolution:**
```
Root Cause: _______________________
Fix Applied: _______________________
Verification: _______________________
```

---

### Scenario C: Duplicate Host Detection (30 min)

**Symptoms:**
When registering a host in k0rdent:
```
Error: Host with UUID 4c4c4544-0000-1234-8041-c7c04f595831 already registered
```

**Investigation Steps:**

1. **Query Existing Hosts**
   ```bash
   # Via k0rdent API
   curl -X GET https://<k0rdent>/api/v1/hosts?uuid=4c4c4544-0000-1234-8041-c7c04f595831 \
     -H "Authorization: Bearer <token>"
   ```

2. **Compare Identifiers**
   ```bash
   # Get UUID from BMC
   curl -k -u admin:password https://192.168.111.12:8000/redfish/v1/Systems/1 | jq '.UUID'

   # Get Serial Number
   curl -k -u admin:password https://192.168.111.12:8000/redfish/v1/Systems/1 | jq '.SerialNumber'

   # Get MAC addresses
   curl -k -u admin:password https://192.168.111.12:8000/redfish/v1/Systems/1/EthernetInterfaces | jq '.Members'
   ```

3. **Check for Hardware Replacement**
   - Was the motherboard replaced?
   - Was the BMC reset?
   - Is this a VM that was cloned?

4. **Review Registration Records**
   ```bash
   # Check both hosts in the system
   kubectl get baremetalhosts -A -o wide
   ```

**Resolution Options:**
- Deregister the old host if it no longer exists
- Update the existing registration if it's the same physical host
- If both hosts exist, one may need a new identifier

```
Root Cause: _______________________
Fix Applied: _______________________
Verification: _______________________
```

---

### Scenario D: Redfish Not Available (45 min)

**Symptoms:**
```bash
$ curl -k -u admin:password https://192.168.111.13:8000/redfish/v1/
curl: (7) Failed to connect to 192.168.111.13 port 8000: Connection refused

# But IPMI works:
$ ipmitool -I lanplus -H 192.168.111.13 -U admin -P password chassis status
System Power         : on
```

**Investigation Steps:**

1. **Verify Redfish Service Status**
   ```bash
   # Check if Redfish is enabled on BMC
   # This varies by vendor - may need web UI or vendor-specific commands
   ```

2. **Check Available Ports**
   ```bash
   # Scan common BMC ports
   nmap -p 80,443,623,8000,5000 192.168.111.13

   # 80/443: Web interface
   # 623: IPMI
   # 8000: Redfish (default for some vendors)
   # 5000: Redfish (alternative port)
   ```

3. **Try Alternative Redfish Ports**
   ```bash
   # Try HTTPS default port
   curl -k -u admin:password https://192.168.111.13/redfish/v1/

   # Try HTTP (not recommended but may work)
   curl -u admin:password http://192.168.111.13/redfish/v1/
   ```

4. **Check Firmware Version**
   ```bash
   # Older BMC firmware may not support Redfish
   ipmitool -I lanplus -H 192.168.111.13 -U admin -P password mc info
   ```

**Decision Tree for Fallback:**
```
Redfish Available?
├── Yes → Use Redfish (preferred)
└── No
    ├── Firmware supports Redfish?
    │   ├── Yes → Enable Redfish in BMC settings
    │   └── No → Firmware upgrade needed
    └── Must use IPMI?
        └── Yes → Configure IPMI-based provisioning
```

**Resolution:**
```
Root Cause: _______________________
Fix Applied: _______________________
Fallback Used: _______________________
Verification: _______________________
```

## Deliverables

Create a troubleshooting runbook document with:

- [ ] **Decision tree** for BMC connectivity issues
- [ ] **Command reference** for each diagnostic step
- [ ] **Resolution documentation** for each scenario
- [ ] **Escalation criteria** - when to involve hardware support

### Template: Troubleshooting Runbook

```markdown
# BMC Troubleshooting Runbook

## Quick Diagnosis

| Symptom | Likely Cause | First Check |
|---------|--------------|-------------|
| Connection refused | Network/Firewall | ping, nc |
| 401 Unauthorized | Credentials | Verify user/pass |
| Duplicate host | UUID conflict | Query existing |
| No Redfish | Disabled/Unsupported | IPMI fallback |

## Detailed Procedures

### Procedure 1: Network Connectivity
[Your documentation here]

### Procedure 2: Authentication Issues
[Your documentation here]

### Procedure 3: Duplicate Detection
[Your documentation here]

### Procedure 4: Protocol Fallback
[Your documentation here]
```

## Verification Checklist

- [ ] Resolved Scenario A (Network connectivity)
- [ ] Resolved Scenario B (Authentication)
- [ ] Resolved Scenario C (Duplicate detection)
- [ ] Resolved Scenario D (Protocol availability)
- [ ] Created troubleshooting runbook
- [ ] Documented all root causes and fixes

## Key Takeaways

1. **Always check basics first** - network, firewall, service status
2. **Have fallback options** - IPMI can supplement Redfish
3. **Stable identifiers matter** - UUID, serial number, MAC address
4. **Document everything** - Future you will thank present you

## Next Steps

With Week 1 complete, proceed to the [Week 1 Quiz](../../week-1-foundations/week-1-quiz.md), then continue to [Week 2: BMaaS](../../week-2-bmaas/README.md)
