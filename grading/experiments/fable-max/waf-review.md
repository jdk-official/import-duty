# Azure security and Well-Architected review: `rg-agentpoc-8e9e55d7`

## 1. Summary

**The estate is not fit to hold anything sensitive, and it is not a pattern to promote as-is.** I found 2 CRITICAL, 3 HIGH, 3 MEDIUM and 5 LOW issues. Severity tags reflect the configuration; the sandbox context lowers the urgency, not the tag. The review was read-only and nothing was changed.

**What I reviewed:** the nine export files in `C:\Users\jdk\import-duty-work\fable-waf\`. The Glob showed no README, CLAUDE.md or ADR in scope.

The estate is in uksouth and has 9 resources, all created 2026-09-18 between 19:35Z and 19:45Z (review date 2026-09-19):
- VNet `10.42.0.0/16`, with `snet-app` (`/24`, delegated to `Microsoft.Web/serverFarms`) and `snet-pe` (`/24`)
- a StorageV2 Standard_LRS account
- one blob private endpoint and its NIC
- the `privatelink.blob.core.windows.net` zone and its VNet link
- a standard Key Vault
- a Log Analytics workspace
- one user-assigned managed identity

There is no compute, no NSG and no alert rule.

**Why the verdict:** the estate has the shape of a private design, but the controls that make that shape effective are off.
- Storage is reachable from every network, anonymous access is permitted, and Shared Key authorisation is on.
- The vault is reachable from every network and has no audit logging.
- The only workload identity holds Contributor on the whole resource group.
- Neither subnet has an NSG.
- The diagnostic settings that exist capture no logs.

I cannot tell from the export whether any of this is a live data exposure. Container access levels and the contents of the storage account and vault were not exported.

All rows in `09-diagnostic-settings.json` are `ok` or `unsupported`, and none are `failed`. So every empty list there is either an authoritative zero or an expected absence. The unknowns come from things that were never queried; they are listed in section 4.

**Create-time-immutable items:** M3 (vault retention fixed at 7 days) and L2 (storage encryption scopes). Neither is wrong for a disposable sandbox. Both need the resource recreated to change, so the fix belongs in the template or script that builds the estate, not on the live resource.

## 2. Findings

### CRITICAL

**C1. The storage public endpoint is open to all networks, so the private endpoint does nothing.**
- **Evidence:** `06-storage.json` has `publicNetworkAccess: Enabled` and `networkRuleSet.defaultAction: Allow`.
- **Why it matters:** per [Learn](https://learn.microsoft.com/en-us/azure/storage/common/storage-private-endpoints), "Creating a private link does not automatically block connections on the public endpoint". Every authentication weakness below (C2, H2) is therefore reachable from the whole internet. Someone set `bypass: None` deliberately, but it has no effect while the default action is `Allow`.
- **Remediation:**
```bicep
// Microsoft.Storage/storageAccounts - properties to change
publicNetworkAccess: 'Disabled'
networkAcls: { defaultAction: 'Deny', bypass: 'None' } // Deny as well, so re-enabling public access does not fall open
```
- **Blocker:** the estate has no private path for operators or pipelines (no VPN, Bastion, jumpbox or in-VNet runner). That is probably why the public endpoint was left open. Decide the access path before closing it.
- **Interim, with stated risk:** keep `Enabled`, set `defaultAction: 'Deny'`, and add one `ipRules` entry for the operator's public IP. Use a single address, not `/32` CIDR. The endpoint stays internet-reachable from that address and the allow-list will drift.

**C2. Anonymous blob access is permitted at account level.**
- **Evidence:** `06-storage.json` has `allowBlobPublicAccess: true`.
- **Why it matters:** the [platform default prohibits anonymous access](https://learn.microsoft.com/en-us/azure/storage/blobs/anonymous-read-access-prevent), so this was set deliberately. It exposes nothing by itself. But any container switched to Blob or Container level becomes readable by anyone, without credentials, from anywhere (because of C1). The Contributor identity in H1 can make that switch through ARM, and blob reads are not evidenced as logged (M2).
- **Remediation:**
  - Check first: `az storage container-rm list --storage-account <acct> -g <rg> --query "[?publicAccess!='None']"`.
  - Then set `allowBlobPublicAccess: false` (`az storage account update --allow-blob-public-access false`).
  - Guard it with the Deny policy rule given in that Learn article.

### HIGH

**H1. The workload identity holds Contributor on the whole resource group.**
- **Evidence:** `08-identity-rbac.json` shows `id-agentpoc-8e9e55d7` with Contributor at RG scope, and no data-plane role at RG scope for any principal.
- **Why it matters:**
  - Contributor includes `listkeys`, which Learn describes as "access [to] all data in a storage account".
  - It can rewrite the storage firewall and the `privatelink` DNS records.
  - It can delete the diagnostic settings and the Log Analytics workspace, which is the sole log sink and sits in the same blast radius.
  - It can [add a federated credential to itself](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust-user-assigned-managed-identity), where Contributor is sufficient. That gives durable access from outside Azure with no secret.
  - The identity is attached to nothing in this RG, so its consumer is unknown.
- **What already limits it:** the vault is in RBAC mode, so Contributor cannot grant itself secret access. [Changing the permission model needs Owner or User Access Administrator](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide).
- **Remediation if it is a runtime identity:** remove the assignment and grant data roles at resource scope.
```bicep
resource raBlob 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: st   // or a single container
  name: guid(st.id, uami.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  properties: {
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
  }
}
// vault scope: Key Vault Secrets User 4633458b-17de-408a-b874-0445c86b69e6
```
- **Remediation if it is a deployment identity:** Contributor on a dedicated sandbox RG is tolerable. Split it from the runtime identity, pin the federated credential subject to one repo and environment, and fix H2 so that `listkeys` stops being a data path.

**H2. Shared Key and SAS authorisation are enabled.**
- **Evidence:** `06-storage.json` has `allowSharedKeyAccess: null` ([null means permitted](https://learn.microsoft.com/en-us/azure/storage/common/shared-key-authorization-prevent)), `defaultToOAuthAuthentication: null`, and `keyPolicy` and `sasPolicy` both null.
- **Why it matters:**
  - Account keys are bearer secrets.
  - They are not attributable to an identity.
  - They are usable from anywhere, given C1.
  - They are exempt from Conditional Access.
  - There is no data-plane RBAC at RG scope, so any data access today is probably key-based. That is an inference, not something the export shows.
- **Remediation:**
  - Assign data roles to the operator and the workload first.
  - Then set `allowSharedKeyAccess: false` and `defaultToOAuthAuthentication: true`.
  - Verified caveats: service and account SAS stop working (user-delegation SAS still works), and Azure Files in the portal and Cloud Shell depend on Shared Key.
  - If keys must stay, set `keyPolicy.keyExpirationPeriodInDays` and a `sasPolicy`.

**H3. The Key Vault is open to all networks, with no private endpoint and no DNS zone.**
- **Evidence:** `07-keyvaults.json` has `publicNetworkAccess: Enabled`, `networkAcls: null` ([firewall disabled](https://learn.microsoft.com/en-us/azure/key-vault/general/network-security)) and `privateEndpointConnections: null`.
- **Why HIGH and not CRITICAL:** Entra authentication is always required, the vault is in RBAC mode, and no data-plane grant is visible. It is still a single-layer defence, and the vault is unaudited (M2).
- **Remediation:**
  - Set `publicNetworkAccess: 'Disabled'` and `networkAcls: { defaultAction: 'Deny', bypass: 'None' }`.
  - Use `bypass: 'AzureServices'` only for a named trusted-service need, because that bypass survives `Disabled`.
  - Add the private endpoint and zone:
```bicep
resource peKv 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-kv-agentpoc'
  location: location
  properties: {
    subnet: { id: snetPe.id }
    privateLinkServiceConnections: [ { name: 'conn-vault', properties: { privateLinkServiceId: kv.id, groupIds: [ 'vault' ] } } ]
  }
  resource zg 'privateDnsZoneGroups' = {
    name: 'default'
    properties: { privateDnsZoneConfigs: [ { name: 'vault', properties: { privateDnsZoneId: kvZone.id } } ] } // zone: privatelink.vaultcore.azure.net, linked to vnet-agentpoc
  }
}
```

### MEDIUM

**M1. Neither subnet has an NSG, and PE network policies are disabled.**
- **Evidence:** `04-nsgs.json` is `[]`. Neither subnet in `03-vnets.json` references an NSG. Both subnets have `privateEndpointNetworkPolicies: Disabled`, so [an NSG would not apply to the private endpoint anyway](https://learn.microsoft.com/en-us/azure/private-link/disable-private-endpoint-network-policy).
- **Why it matters:** exposure today is nil, because there is no compute, no peering and no gateway. It becomes real when an app tier lands.
- **Remediation for `snet-pe`:** attach the NSG below and set `privateEndpointNetworkPolicies: 'NetworkSecurityGroupEnabled'`.
```bicep
securityRules: [
  { name: 'Allow-App-To-PE-443', properties: { priority: 100, direction: 'Inbound', access: 'Allow', protocol: 'Tcp', sourceAddressPrefix: '10.42.1.0/24', sourcePortRange: '*', destinationAddressPrefix: '10.42.2.0/24', destinationPortRange: '443' } }
  { name: 'Deny-All-Inbound', properties: { priority: 4096, direction: 'Inbound', access: 'Deny', protocol: '*', sourceAddressPrefix: '*', sourcePortRange: '*', destinationAddressPrefix: '*', destinationPortRange: '*' } }
]
```
- **Remediation for `snet-app`:** use the same explicit deny-all inbound. On an integration subnet [inbound rules do not apply to the app](https://learn.microsoft.com/en-us/azure/app-service/overview-vnet-integration); the NSG's value there is egress control. Add egress allow rules plus a deny once the app's dependencies are known.
- **Pitfall:** redeploying the VNet with incomplete inline subnet definitions wipes the delegation and breaks the private endpoint.

**M2. The logging looks configured but collects no logs.**
- **Evidence from `09-diagnostic-settings.json`:**
  - Key Vault: status `ok`, empty list. That is an authoritative zero, so there is no `AuditEvent` logging.
  - `diag-storage`: `logs: []`, only the Transaction metric enabled, Capacity disabled.
  - `diag-vnet`: its only log category, `VMProtectionAlerts`, has `enabled: false`; only metrics are shipped.
  - Workspace: status `ok`, empty list, so no query audit.
- **What is unknown:** storage resource logs are [collected only through a diagnostic setting](https://learn.microsoft.com/en-us/azure/storage/blobs/monitor-blob-storage), and it is created per storage service on `.../blobServices/default` ([Learn](https://learn.microsoft.com/en-us/azure/storage/common/transport-layer-security-configure-minimum-version)). That ID was never queried, so blob logging is unknown, not zero.
- **Why it matters:** an audit that only checks whether a diagnostic setting exists would pass this estate.
- **Remediation:** add `diag-kv` on the vault with `category: 'AuditEvent'`. Add `diag-blob` scoped to `blobServices/default` with `StorageRead`, `StorageWrite` and `StorageDelete`. Send both to the existing workspace. I would not chase the empty `ok` rows on the private endpoint, NIC or DNS zone; those types carry metrics only (from my knowledge, not verified this session).

**M3 [IMMUTABLE]. The vault has purge protection off and 7-day retention fixed at creation.**
- **Evidence:** `07-keyvaults.json` has `enablePurgeProtection: null` and `softDeleteRetentionInDays: 7`.
- **Why it matters:** retention ["can't be changed afterwards"](https://learn.microsoft.com/en-us/azure/key-vault/general/soft-delete-overview). Purge protection, once on, ["cannot be disabled or overridden by anyone including Microsoft"](https://learn.microsoft.com/en-us/azure/key-vault/general/key-vault-recovery), and it blocks reuse of the vault name for the retention period.
- **For this sandbox, leaving it off is defensible.** The risk is that a delete followed by a purge destroys the secrets permanently. Purge needs a subscription-level permission, so the H1 identity cannot do it.
- **Remediation:**
  - Make the template default `enablePurgeProtection: true` and `softDeleteRetentionInDays: 90`, with an explicit sandbox override.
  - Never promote this vault.
  - Any customer-managed-key use requires purge protection.

### LOW

**L1. Only the blob sub-resource has a private endpoint.**
- After C1, the dfs, file, queue, table and web endpoints become unreachable.
- That is fine if only blob is used.
- If `snet-app` will host a Functions app, its host storage needs blob, queue, table and file endpoints, each with its own [zone](https://learn.microsoft.com/en-us/azure/storage/common/storage-private-endpoints).

**L2 [IMMUTABLE]. Storage encryption scopes were fixed at creation.**
- `requireInfrastructureEncryption: null` [cannot be enabled later](https://learn.microsoft.com/en-us/azure/storage/common/infrastructure-encryption-enable).
- The queue and table key scope is Service, so [they can never take a customer-managed key](https://learn.microsoft.com/en-us/azure/storage/common/account-encryption-key-create).
- This matters only under a compliance requirement, and none was stated. No action for the sandbox.
- If compliance scope appears, set the properties in the template:
  - `encryption.requireInfrastructureEncryption: true`
  - `encryption.services.queue.keyType: 'Account'` and `encryption.services.table.keyType: 'Account'` (Table is billed at a different rate with this scope)

**L3. `snet-pe` has no `defaultOutboundAccess` value.**
- [Null implicitly allows outbound](https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/default-outbound-access) for any future VM. Set it to `false`.
- The `false` on `snet-app` has no effect, because private subnets "aren't applicable to delegated... subnets". The future app's egress needs explicit design (app routing, plus a NAT gateway if needed).

**L4. Governance hygiene.**
- **Evidence:** the RG is tagged `disposable=true` with no `owner` or expiry tag, the resources carry no tags, and there are no alert rules or action groups in the RG.
- **Why it matters:** the realistic risk is that this estate lingers with open endpoints.
- **Remediation:** add `owner` and `expires-on` tags, a tag-inheritance policy, and teardown automation.

**L5. A user holds standing Owner at subscription scope, and it is the only human owner visible.**
- This is acceptable for a personal sandbox. Otherwise use PIM eligibility plus a second break-glass owner.
- Deep RBAC and Conditional Access audit belongs to the dedicated auditors, not this review.

**Suggested order** (the estate has no compute, so these can probably be one change):
1. C2 (disallow anonymous access).
2. M2 (turn logging on).
3. Assign data-plane roles.
4. Decide the access path, then C1, H3 and M1.
5. H1, then H2.

## 3. Well-Architected notes

**Reliability**
- No SLA, RTO or RPO was stated, so I make no achievability claim.
- The estate is single-region. Storage is LRS with `zones: null`.
- The vault is platform-replicated, so deletion is the realistic loss scenario, not an outage.
- Blob soft delete and versioning were not exported.
- This is appropriate for a disposable estate. If it is promoted, LRS to ZRS is a later conversion rather than an immutable choice (regional availability not verified this session).

**Security**
- The gaps are listed in section 2.
- Positives:
  - the vault uses RBAC mode and all its `enabledFor*` flags are false
  - HTTPS-only
  - `TLS1_2`, which is the [highest value Storage can enforce](https://learn.microsoft.com/en-us/azure/storage/common/transport-layer-security-configure-minimum-version); TLS 1.3 negotiates automatically
  - cross-tenant replication off
  - a managed identity in place of secrets
  - the private endpoint approved
  - the DNS zone linked to the VNet without auto-registration
  - a dedicated private-endpoint subnet
  - DDoS protection off, which is correct because there are no public IPs

**Cost Optimization**
- The estate is tiny, and LRS is the right choice for it.
- The cost risk is lifetime (L4), not size.
- Budgets were not exported, and I am not quoting prices I have not verified.

**Operational Excellence**
- Resources were created one after another by a user over about 10 minutes. The vault's `systemData.createdByType` is `User`.
- Some settings deviate from platform defaults in both directions.
- This suggests a hand-assembled estate rather than IaC. That is an inference; deployment history was not exported.
- Codify the estate and add policy guardrails. IaC authoring belongs to `devops-infrastructure-expert`, with `terraform-import` and `avm-refactor` as applicable.

**Performance Efficiency**
- There is no workload and no throughput target, so I cannot say which limit would bind first.
- The export contains no elastic tier, so there is no scaling configuration to sign off.
- Verified ceilings to carry into the app-tier design:
  - **`snet-app` `/24`:** 251 usable addresses, one per plan instance, temporarily doubled during scale operations, and the size "can't be changed after assignment". Cap total instances at 125 or fewer.
  - **[Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/service-limits):** 4,000 transactions per 10 seconds per vault, 300 per 10 seconds for creates, and HTTP 429 when throttled. Use Key Vault references or caching, never per-request secret reads.
  - **[Storage](https://learn.microsoft.com/en-us/azure/storage/common/scalability-targets-standard-account):** 40,000 requests per second per account in UK South, plus per-partition limits that surface as 503 or 500 errors.
  - **Log Analytics daily cap:** unknown.

## 4. Open questions and assumptions

1. What data is in the storage account and the vault, and is any container public? This decides whether C1 and C2 are latent or live.
2. What assumes `id-agentpoc-8e9e55d7`, and is it a deployment or a runtime identity? Federated credentials were not exported.
3. Where do operators and pipelines connect from? This blocks the `Disabled` setting in C1 and H3.
4. What will land in `snet-app`: a Web App or Functions? `snet-app` carries no `serviceAssociationLinks`, which is consistent with nothing being integrated yet. If the app should be private inbound, it needs its own private endpoint and zone.
5. Is the blob A record managed by a DNS zone group? `customDnsConfigs: []` plus 2 record sets is consistent with yes. Verify with `az network private-endpoint dns-zone-group list`.
6. **Not in the export, so unknown rather than zero:**
   - container access levels
   - blob soft delete and versioning
   - diagnostic settings on the storage sub-services
   - role assignments scoped directly to child resources (file 08 covers RG scope plus inherited)
   - the workspace's properties (retention, cap, public ingestion and query)
   - Activity Log export
   - Defender plans
   - Policy assignments
   - budgets
7. Will `10.42.0.0/16` ever be peered? There is no overlap or peering today. Allocate it through IPAM before joining a hub.
8. **Assumptions:**
   - I treated absent subnet keys (`networkSecurityGroup`, `routeTable`, `natGateway`, `serviceEndpoints`) as not set.
   - Existing resource names are valid by construction.
   - The names I propose (`pe-kv-agentpoc`, `nsg-snet-pe`, `nsg-snet-app`, `diag-kv`, `diag-blob`) are within limits from memory, not re-verified.

**Verification status**
- **Verified on Microsoft Learn:** the linked claims above were verified through WebFetch. The Learn MCP tools were not callable in this session.
- **Not verified:**
  - that the API versions in the snippets are the latest (they are known-valid; pin them when authoring). One oversized fetch result was saved outside the permitted directory and I did not read it.
  - the storage role GUID
  - built-in policy display names
- **Not consulted:**
  - the house `references/` pattern library, which sits outside the permitted read scope, so it is not cited
  - live tenant state (this review is export-only)

**Files reviewed** (all in `C:\Users\jdk\import-duty-work\fable-waf\`):
- `01-resources.json`
- `02-resource-group.json`
- `03-vnets.json`
- `04-nsgs.json`
- `05-private-networking.json`
- `06-storage.json`
- `07-keyvaults.json`
- `08-identity-rbac.json`
- `09-diagnostic-settings.json`
