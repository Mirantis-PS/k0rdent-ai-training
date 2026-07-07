# Lab 2.1 - Explore k0rdent Sandbox

**Duration:** 3 hours
**Type:** Exploration / Familiarization

## Objective

Familiarize yourself with the k0rdent UI and API by exploring a pre-configured sandbox environment.

## Prerequisites

- Access to k0rdent sandbox environment (credentials provided separately)
- Web browser (Chrome or Firefox recommended)
- Terminal with curl installed

## Lab Environment

This lab uses a shared sandbox environment with pre-configured:
- Sample tenants
- Demo clusters
- Example workloads

## Tasks

### Task 1: Provider Console Exploration (45 min)

1. **Log into Provider Console**
   - Navigate to the Provider Console URL
   - Authenticate using provided credentials
   - Note the initial dashboard view

2. **Explore Navigation**
   - Infrastructure section
   - Tenants section
   - Clusters section
   - Service Catalog section
   - Settings/Administration

3. **Review Pre-configured Tenants**
   - List all tenants
   - Note resource allocations
   - Review tenant states (Active, Suspended)

4. **Examine Infrastructure**
   - View registered bare metal hosts
   - Check hypervisor clusters
   - Review available resources

### Task 2: API Exploration (45 min)

1. **Access API Documentation**
   - Navigate to API docs section
   - Review available endpoints
   - Understand authentication method

2. **Obtain API Token**
   ```bash
   # Example: Get API token
   curl -X POST https://<k0rdent-url>/api/v1/auth/token \
     -H "Content-Type: application/json" \
     -d '{"username": "<user>", "password": "<pass>"}'
   ```

3. **Execute Sample Queries**
   ```bash
   # List tenants
   curl -X GET https://<k0rdent-url>/api/v1/tenants \
     -H "Authorization: Bearer <token>"

   # Get specific tenant
   curl -X GET https://<k0rdent-url>/api/v1/tenants/<tenant-id> \
     -H "Authorization: Bearer <token>"

   # List clusters
   curl -X GET https://<k0rdent-url>/api/v1/clusters \
     -H "Authorization: Bearer <token>"
   ```

4. **Review API Response Structure**
   - Examine JSON response format
   - Note pagination patterns
   - Identify resource relationships

### Task 3: Customer Console Exploration (45 min)

1. **Switch to Customer Console**
   - Navigate to Customer Console URL
   - Log in as a tenant user

2. **Explore Tenant View**
   - Dashboard for tenant resources
   - Available quotas
   - Deployed workloads

3. **Compare Consoles**
   - What's visible in Provider but not Customer console?
   - What actions can tenant users perform?
   - How is isolation enforced in the UI?

### Task 4: Audit Log Review (30 min)

1. **Access Audit Logs**
   - Navigate to audit log section in Provider Console
   - Or query via API:
   ```bash
   curl -X GET https://<k0rdent-url>/api/v1/audit-logs \
     -H "Authorization: Bearer <token>"
   ```

2. **Review Recent Activities**
   - Filter by time range
   - Filter by action type
   - Filter by user

3. **Understand Audit Structure**
   - What information is captured?
   - How are actions attributed?
   - What's the retention policy?

## Deliverables

Complete these items before proceeding:

- [ ] Screenshot of Provider Console dashboard
- [ ] Sample API response from tenant list query (save as `tenant-list.json`)
- [ ] Screenshot of Customer Console from tenant perspective
- [ ] Notes file with observations on UI/UX differences between consoles
- [ ] Audit log excerpt showing at least 5 different action types

## Verification Checklist

- [ ] Successfully logged into Provider Console
- [ ] Explored all main navigation sections
- [ ] Obtained and used API token
- [ ] Successfully queried at least 3 API endpoints
- [ ] Logged into Customer Console as tenant user
- [ ] Reviewed audit logs

## Troubleshooting

### Cannot Access Provider Console
- Verify URL is correct
- Check network connectivity
- Ensure credentials are valid
- Contact instructor if issues persist

### API Token Not Working
- Token may have expired (typical TTL: 1 hour)
- Regenerate token
- Check token format in Authorization header

### Customer Console Access Denied
- Ensure using tenant user credentials, not admin
- Check tenant is in Active state
- Verify user is assigned to tenant

## Notes

Record any observations, questions, or issues encountered:

```
--- YOUR NOTES HERE ---




```

## Next Lab

Proceed to [Lab 2.2 - BMC Discovery with Redfish](lab-2.2-bmc-discovery.md)
