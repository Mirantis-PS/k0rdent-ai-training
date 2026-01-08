# Lab 2.2 - BMC Discovery with Redfish

**Duration:** 4 hours
**Type:** Hands-on Technical

## Objective

Register and query bare metal hosts using the Redfish API, preparing for automated provisioning.

## Prerequisites

- Completed Lab 2.1
- Lab environment provisioned (Metal3 Dev type)
- SSH access to lab VM

## Lab Environment

Your lab environment includes:
- 1 management VM with tools installed
- 3 virtual bare metal hosts with BMC emulation (sushy-tools)
- Network connectivity between management and BMC endpoints

**Environment Details:**
| Host | BMC IP | Purpose |
|------|--------|---------|
| node-1 | 192.168.111.1:8000 | Control plane |
| node-2 | 192.168.111.2:8000 | Worker |
| node-3 | 192.168.111.3:8000 | Worker |

**Default BMC Credentials:** admin / password

## Tasks

### Task 1: Discover Redfish Service Root (30 min)

1. **SSH to Management VM**
   ```bash
   ssh lab-user@<management-vm-ip>
   ```

2. **Query Redfish Service Root**
   ```bash
   # Discover available resources
   curl -k -u admin:password \
     https://192.168.111.1:8000/redfish/v1/
   ```

3. **Understand the Response**
   ```json
   {
     "@odata.type": "#ServiceRoot.v1_5_0.ServiceRoot",
     "Id": "RootService",
     "Name": "Root Service",
     "Systems": {"@odata.id": "/redfish/v1/Systems"},
     "Chassis": {"@odata.id": "/redfish/v1/Chassis"},
     "Managers": {"@odata.id": "/redfish/v1/Managers"},
     ...
   }
   ```

4. **Document Available Endpoints**
   - Systems (compute resources)
   - Chassis (physical enclosure)
   - Managers (BMC itself)

### Task 2: Query System Information (45 min)

1. **Get System Details**
   ```bash
   curl -k -u admin:password \
     https://192.168.111.1:8000/redfish/v1/Systems/1 | jq .
   ```

2. **Extract Key Information**
   - UUID
   - Serial Number
   - Model
   - Power State
   - Boot configuration

3. **Get Processor Information**
   ```bash
   curl -k -u admin:password \
     https://192.168.111.1:8000/redfish/v1/Systems/1/Processors | jq .

   # Get specific processor
   curl -k -u admin:password \
     https://192.168.111.1:8000/redfish/v1/Systems/1/Processors/CPU1 | jq .
   ```

4. **Get Memory Information**
   ```bash
   curl -k -u admin:password \
     https://192.168.111.1:8000/redfish/v1/Systems/1/Memory | jq .
   ```

5. **Get Storage Information**
   ```bash
   curl -k -u admin:password \
     https://192.168.111.1:8000/redfish/v1/Systems/1/Storage | jq .
   ```

6. **Get Network Interfaces**
   ```bash
   curl -k -u admin:password \
     https://192.168.111.1:8000/redfish/v1/Systems/1/EthernetInterfaces | jq .
   ```

### Task 3: Power Management (45 min)

1. **Check Current Power State**
   ```bash
   curl -k -u admin:password \
     https://192.168.111.1:8000/redfish/v1/Systems/1 | jq '.PowerState'
   ```

2. **Perform Power On**
   ```bash
   curl -k -u admin:password -X POST \
     -H "Content-Type: application/json" \
     -d '{"ResetType": "On"}' \
     https://192.168.111.1:8000/redfish/v1/Systems/1/Actions/ComputerSystem.Reset
   ```

3. **Perform Graceful Shutdown**
   ```bash
   curl -k -u admin:password -X POST \
     -H "Content-Type: application/json" \
     -d '{"ResetType": "GracefulShutdown"}' \
     https://192.168.111.1:8000/redfish/v1/Systems/1/Actions/ComputerSystem.Reset
   ```

4. **Perform Force Restart**
   ```bash
   curl -k -u admin:password -X POST \
     -H "Content-Type: application/json" \
     -d '{"ResetType": "ForceRestart"}' \
     https://192.168.111.1:8000/redfish/v1/Systems/1/Actions/ComputerSystem.Reset
   ```

5. **Document All Reset Types**
   - On
   - ForceOff
   - GracefulShutdown
   - GracefulRestart
   - ForceRestart
   - PushPowerButton

### Task 4: Boot Configuration (45 min)

1. **Get Current Boot Configuration**
   ```bash
   curl -k -u admin:password \
     https://192.168.111.1:8000/redfish/v1/Systems/1 | jq '.Boot'
   ```

2. **Set One-Time Network Boot**
   ```bash
   curl -k -u admin:password -X PATCH \
     -H "Content-Type: application/json" \
     -d '{
       "Boot": {
         "BootSourceOverrideEnabled": "Once",
         "BootSourceOverrideTarget": "Pxe"
       }
     }' \
     https://192.168.111.1:8000/redfish/v1/Systems/1
   ```

3. **Set Persistent Boot Order**
   ```bash
   curl -k -u admin:password -X PATCH \
     -H "Content-Type: application/json" \
     -d '{
       "Boot": {
         "BootSourceOverrideEnabled": "Continuous",
         "BootSourceOverrideTarget": "Hdd"
       }
     }' \
     https://192.168.111.1:8000/redfish/v1/Systems/1
   ```

4. **Verify Boot Configuration Changed**
   ```bash
   curl -k -u admin:password \
     https://192.168.111.1:8000/redfish/v1/Systems/1 | jq '.Boot'
   ```

### Task 5: Virtual Media (45 min)

1. **List Virtual Media Resources**
   ```bash
   curl -k -u admin:password \
     https://192.168.111.1:8000/redfish/v1/Managers/BMC/VirtualMedia | jq .
   ```

2. **Get CD-ROM Virtual Media Status**
   ```bash
   curl -k -u admin:password \
     https://192.168.111.1:8000/redfish/v1/Managers/BMC/VirtualMedia/Cd | jq .
   ```

3. **Mount ISO Image**
   ```bash
   curl -k -u admin:password -X POST \
     -H "Content-Type: application/json" \
     -d '{
       "Image": "http://192.168.111.100/images/ubuntu-22.04.iso",
       "Inserted": true,
       "WriteProtected": true
     }' \
     https://192.168.111.1:8000/redfish/v1/Managers/BMC/VirtualMedia/Cd/Actions/VirtualMedia.InsertMedia
   ```

4. **Verify Mount**
   ```bash
   curl -k -u admin:password \
     https://192.168.111.1:8000/redfish/v1/Managers/BMC/VirtualMedia/Cd | jq '.Inserted, .Image'
   ```

5. **Eject Virtual Media**
   ```bash
   curl -k -u admin:password -X POST \
     https://192.168.111.1:8000/redfish/v1/Managers/BMC/VirtualMedia/Cd/Actions/VirtualMedia.EjectMedia
   ```

### Task 6: Repeat for All Nodes (30 min)

1. **Create Inventory Script**
   ```bash
   #!/bin/bash
   # inventory.sh

   NODES=("192.168.111.1:8000" "192.168.111.2:8000" "192.168.111.3:8000")
   USER="admin"
   PASS="password"

   for node in "${NODES[@]}"; do
     echo "=== Node: $node ==="
     curl -k -s -u $USER:$PASS \
       https://$node/redfish/v1/Systems/1 | \
       jq '{UUID: .UUID, SerialNumber: .SerialNumber, PowerState: .PowerState, Model: .Model}'
     echo ""
   done
   ```

2. **Run Inventory**
   ```bash
   chmod +x inventory.sh
   ./inventory.sh > hardware-inventory.json
   ```

## Deliverables

- [ ] JSON output of system hardware inventory for all 3 nodes (`hardware-inventory.json`)
- [ ] Screenshot showing successful power cycle
- [ ] Boot order configuration changes documented
- [ ] Virtual media mount verification

## Verification Checklist

- [ ] Successfully queried Redfish service root
- [ ] Retrieved CPU, memory, storage, and network info
- [ ] Performed power on/off/restart operations
- [ ] Modified boot configuration
- [ ] Mounted virtual media ISO
- [ ] Created inventory for all nodes

## Troubleshooting

### Connection Refused
```bash
# Verify sushy-tools is running
systemctl status sushy-tools

# Check port is listening
ss -tlnp | grep 8000
```

### Authentication Failed
```bash
# Verify credentials
curl -k -u admin:password https://192.168.111.1:8000/redfish/v1/

# If 401, check credentials are correct
```

### Virtual Media Mount Fails
```bash
# Verify ISO URL is accessible from BMC network
curl -I http://192.168.111.100/images/ubuntu-22.04.iso

# Check virtual media support
curl -k -u admin:password \
  https://192.168.111.1:8000/redfish/v1/Managers/BMC/VirtualMedia
```

## Key Takeaways

1. **Redfish provides a modern, REST-based API** for server management
2. **Common operations** include:
   - Hardware discovery
   - Power management
   - Boot configuration
   - Virtual media for remote installation
3. **Authentication** is typically Basic Auth over HTTPS
4. **The Systems endpoint** is where most compute-related information lives

## Next Lab

Proceed to [Lab 2.3 - Troubleshooting BMC Connectivity](lab-2.3-troubleshooting-bmc.md)
