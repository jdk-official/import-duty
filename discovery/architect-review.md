# Azure estate review — rg-agentpoc-8e9e55d7

**Reviewed:** 2026-09-18 · **Scope:** single resource group, `rg-agentpoc-8e9e55d7` (uksouth)
**Source:** live export `01-resources.json` … `09-diagnostic-settings.json`
**Produced by:** `expert-agents:azure-architect` (opus), scoped to `discovery/` only
**Stated context:** non-production sandbox. No SLA, RTO, RPO, throughput target or compliance scope stated.

> Transcribed from the agent's reply. The agent holds no `Write` tool by design —
> it is advisory and cannot mutate anything, including its own output file.

## 1. Summary

Nine resources: one VNet with two subnets, a Log Analytics workspace, a StorageV2 account, a blob private endpoint with its NIC and `privatelink.blob.core.windows.net` zone plus VNet link, a Key Vault, and a user-assigned managed identity.

The shape of the build is right — private endpoint, private DNS zone, VNet link, RBAC-authorised vault, user-assigned identity, central workspace. The enforcement is not. The storage account keeps `publicNetworkAccess: Enabled` with a `defaultAction: Allow` firewall, so the private endpoint adds a private path without removing the public one. The Key Vault has no network ACLs and no private endpoint. There are no network security groups anywhere in the resource group. The result is a private-networking layer that is decorative rather than load-bearing.

**Headline verdict: not fit to hold anything beyond throwaway test data.** For a disposable sandbox with synthetic data this is tolerable and cheap to fix; the concern is that this pattern is labelled `agent-pipeline-poc` and PoC shapes get copied forward. The three fix-first items are the storage network posture, the Key Vault network posture, and the absence of NSGs. One item is already immutable: the vault's 7-day soft-delete retention interval, settable only at creation.

No naming violation found: `stagentpoc8e9e55d7` is 18 characters (limit 3–24); `kv-agentpoc-8e9e55d7` is 20 (limit 24).

---

## 2. Findings

### CRITICAL-1 — Storage account reachable from the public internet; the private endpoint is decorative

`publicNetworkAccess: "Enabled"` with `networkRuleSet.defaultAction: "Allow"`, empty `ipRules` and empty `virtualNetworkRules`. A private endpoint (`pe-blob-agentpoc`, group `blob`) exists and is approved.

`defaultAction: Allow` admits every source address on the internet. The private endpoint creates an additional private path; it does not close the public one. Every control depending on network isolation — the private DNS zone, the PE subnet, the VNet link — is providing assurance it cannot deliver. This is why it outranks the anonymous-access flag below.

**Remediation.**

```bicep
properties: {
  publicNetworkAccess: 'Disabled'
  networkAcls: {
    defaultAction: 'Deny'
    bypass: 'None'
    ipRules: []
    virtualNetworkRules: []
  }
}
```

Sequencing matters: confirm the deployment identity reaches the account over the private endpoint (or add a temporary `ipRules` entry for the operator's egress address) before flipping `publicNetworkAccess`, or you lock yourself out of the data plane.

### HIGH-2 — Anonymous blob access permitted at account level

`allowBlobPublicAccess: true`, set explicitly — current portal/ARM paths default to `false`.

Verified against Microsoft Learn (*Configure anonymous read access for containers and blobs*, 2026-08): the account flag alone does not expose data — a container's access level must also be `Blob` or `Container`. So this is a precondition, not a live exposure, which is why it sits below CRITICAL-1. But anonymous, unauthenticated, unlogged public read is one container-ACL change away. Container access levels were not in the export, so it cannot be confirmed no container is already public.

Disallowing anonymous access does not affect the `$web` container used by static website hosting, which is always publicly readable. The account exposes a `web` endpoint — confirm whether static website hosting is on.

**Remediation.** `allowBlobPublicAccess: false`, then enumerate containers:

```powershell
az storage container list --account-name stagentpoc8e9e55d7 --auth-mode login `
  --query "[].{name:name, access:properties.publicAccess}" -o table
```

Back it with the built-in policy *Storage accounts should prevent anonymous access* in Deny mode.

### HIGH-3 — Shared Key authorization permitted, and the RG Contributor assignment grants access to the keys

`allowSharedKeyAccess: null`. Verified against Learn (*Prevent authorization with Shared Key*, 2026-08): the property "is not set by default and does not return a value until you explicitly set it… the storage account permits requests that are authorized with Shared Key when the property value is null or when it is true." Account-key authorization is live.

Separately, `id-agentpoc-8e9e55d7` holds **Contributor** at resource-group scope. Contributor includes `Microsoft.Storage/storageAccounts/listkeys/action`.

These compose into a control bypass. The identity has no data-plane role on the storage account, yet it can call `listKeys`, obtain the account key, and read and write every blob, file, queue and table. That access is authorised as the account, not the identity — indistinguishable in logs from any other key holder, ignores RBAC scoping entirely, and cannot be brought under Conditional Access (Learn is explicit that disallowing Shared Key is a prerequisite). The managed identity currently provides the *appearance* of keyless access while the real path is a shared secret.

**Remediation.** `allowSharedKeyAccess: false`, `defaultToOAuthAuthentication: true`, plus a resource-scoped data-plane role:

```bicep
resource blobDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: sa
  name: guid(sa.id, uami.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  properties: {
    // Storage Blob Data Contributor — scoped to the account, not the RG
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}
```

### HIGH-4 — Key Vault accepts traffic from the public internet

`publicNetworkAccess: "Enabled"`, `networkAcls: null`, `privateEndpointConnections: null`.

`networkAcls: null` means no firewall at all — the data plane answers from any source address, with only Entra authentication and RBAC in front. There is no private endpoint and no `privatelink.vaultcore.azure.net` zone, so a workload in `snet-app` would reach the vault publicly even though storage has a private path. The network design is inconsistent with itself.

The vault has `enableRbacAuthorization: true`, an empty `accessPolicies` array, and no role assignment granting any principal data-plane access. That limits blast radius today — and means the vault is not yet usable by the workload (see MEDIUM-8).

**Remediation.** Private endpoint with group ID `vault`, a `privatelink.vaultcore.azure.net` zone linked to `vnet-agentpoc`, `publicNetworkAccess: 'Disabled'`, `networkAcls.defaultAction: 'Deny'` with `bypass: 'AzureServices'` only if template deployment references require it.

### HIGH-5 — No network security groups exist anywhere in the resource group

`04-nsgs.json` is empty. Neither `snet-app` (10.42.1.0/24, delegated `Microsoft.Web/serverFarms`) nor `snet-pe` (10.42.2.0/24) has an NSG.

Without an NSG the subnets fall back to Azure defaults: all inbound permitted within the VNet, all outbound to the internet. There is no default-deny anywhere. Free lateral movement between `snet-app` and `snet-pe` is the specific risk — a compromised app instance reaches the storage private endpoint with nothing in the path to stop or record it.

**Remediation.** One NSG per subnet with an explicit deny-all inbound at priority 4096 beneath the rules the workload needs; for `snet-pe`, permit 443 from `10.42.1.0/24` only. Read together with MEDIUM-7 — on `snet-pe` an NSG alone will not take effect.

### HIGH-6 — Key Vault has no diagnostic settings; secret access is unlogged

`09-diagnostic-settings.json` reports the vault `status: "ok"` with an empty settings list — authoritative.

Key Vault's `AuditEvent` log is the only record of who read which secret, key or certificate, and when. Without it there is no way to answer "was this secret accessed?" after an incident, and no way to detect anomalous retrieval during one. A Log Analytics workspace already exists in the same resource group, so this is a few lines of configuration. The vault is the highest-value resource in the estate and currently the least observable.

**Remediation.**

```bicep
resource kvDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: kv
  name: 'diag-kv'
  properties: {
    workspaceId: law.id
    logs: [
      { categoryGroup: 'audit',   enabled: true }
      { categoryGroup: 'allLogs', enabled: true }
    ]
    metrics: [ { category: 'AllMetrics', enabled: true } ]
  }
}
```

Prefer `categoryGroup` over enumerating categories so new ones are captured automatically.

### MEDIUM-7 — Private endpoint network policies disabled on `snet-pe`

`privateEndpointNetworkPolicies: "Disabled"` on the subnet, `privateEndpointVNetPolicies: "Disabled"` on the VNet.

Verified against Learn (*Manage network policies for private endpoints*): this is the platform default, not a regression. But it is a trap for HIGH-5 — attaching an NSG to `snet-pe` while this stays Disabled produces a control that appears configured in the portal and silently does not filter private endpoint traffic. Same for any UDR intended to force PE traffic through a firewall.

**Remediation.** Set `privateEndpointNetworkPolicies: 'Enabled'` at the same time as the NSG, not after.

### MEDIUM-8 — The managed identity is over-privileged for control plane and under-privileged for data plane

`id-agentpoc-8e9e55d7` holds Contributor (`b24988ac-6180-42a0-ab88-20f7382dd24c`) at RG scope, no condition, no description. It holds no data-plane role on the storage account or the vault within the exported scope.

Two problems from one assignment. Contributor at RG scope lets the identity create, reconfigure and delete every resource in the group — including deleting the Key Vault, rewriting the storage firewall, or removing the private endpoint. For a pipeline identity that presumably reads configuration and writes blobs, that is far more than it needs. Second, because it has no data-plane role, the only way it reaches data is through account keys (HIGH-3) — the over-broad control-plane grant is what makes the insecure data path available.

Contributor cannot itself grant RBAC roles, so this is not a direct escalation path to Owner; the risk is destructive and lateral.

**Remediation.** Remove the RG-scoped Contributor. Replace with resource-scoped roles matching the actual job — Storage Blob Data Contributor on the account, Key Vault Secrets User (`4633458b-17de-408a-b874-0445c86b69e6`) on the vault. If it genuinely needs to deploy, scope a purpose-built custom role rather than reaching for Contributor.

### MEDIUM-9 — Key Vault purge protection off, and the 7-day retention window is already immutable

`enablePurgeProtection: null` with `enableSoftDelete: true` and `softDeleteRetentionInDays: 7`.

Verified against Learn (*Azure Key Vault soft-delete*, 2026-04): soft-delete is on by default and cannot be disabled; purge protection is "not enabled by default"; and "the retention policy interval can only be configured during key vault creation and can't be changed afterwards." The default is 90 days, so 7 was chosen deliberately.

Without purge protection, anyone holding purge rights — including the subscription Owner in LOW-13 — can permanently destroy the vault or its contents immediately, with no recovery window. The 7-day retention is the shortest permitted and **cannot be lengthened on this vault**: changing it requires deleting and recreating it. This is the one create-time-immutable decision in the estate.

Learn also notes most Azure services integrating with Key Vault — Storage among them — *require* purge protection before using a vault-held key. If customer-managed keys are ever intended (MEDIUM-11), this vault cannot support them as built.

**Remediation.** For the sandbox as it stands, 7 days is defensible given the `disposable: true` tag — but record it as a deliberate acceptance, not an oversight. Purge protection can still be enabled in place (and is itself irreversible). If promoted beyond the sandbox, recreate with 90 days.

### MEDIUM-10 — Observability partial: no storage data-plane logs, no workspace audit, VNet metrics only

Three gaps, all from `status: "ok"` rows:

- **Storage** (`diag-storage`): `logs: []`, only the `Transaction` metric enabled (`Capacity` disabled). No data-plane logs.
- **Log Analytics workspace**: no diagnostic settings.
- **VNet** (`diag-vnet`): `AllMetrics` on, but its only log category `VMProtectionAlerts` explicitly `enabled: false`.

Blob read/write/delete logging (`StorageBlobLogs`) comes from a diagnostic setting on the **blob service** sub-resource (`.../blobServices/default`), not the account. That sub-resource is not in the export, so its state is unknown — but the account-level setting shown cannot carry those logs regardless. This also blocks the detection step Microsoft recommends before disabling Shared Key (HIGH-3): the documented `StorageBlobLogs | where AuthenticationType in ("AccountKey","SAS")` query has no data to run against, so you cannot measure what would break.

**Remediation.** Add a diagnostic setting on `.../blobServices/default` with `StorageRead`, `StorageWrite`, `StorageDelete`. Add an `audit` setting on the workspace pointing at itself. Enable `Capacity` metrics. Confirm VNet flow logs in Network Watcher (out of export scope).

### MEDIUM-11 — No SAS expiry policy, no key rotation policy, no infrastructure encryption

`sasPolicy: null`, `keyPolicy: null`, `encryption.requireInfrastructureEncryption: null`, `encryption.keySource: "Microsoft.Storage"`. Both account keys created at account creation and never rotated.

While Shared Key remains enabled (HIGH-3), nothing bounds how long an issued SAS stays valid — a token minted with a ten-year expiry is a durable, unrevocable credential that appears in no RBAC review. A `keyPolicy` sets a rotation reminder so stale keys surface in Defender for Cloud and Azure Policy rather than ageing silently.

Infrastructure encryption and customer-managed keys are both absent. **Neither is a finding on its own** — platform-managed encryption at rest is on (`blob` and `file` both enabled) and is sufficient absent a stated compliance requirement, and none was stated. They are noted because `requireInfrastructureEncryption` is create-time-immutable: a future workload needing it cannot upgrade this account in place. CMK would additionally require purge protection, which MEDIUM-9 shows is off.

**Remediation.** Preferred fix is HIGH-3 — disabling Shared Key makes both policies moot. If Shared Key must stay: `sasExpirationPeriod: '0.08:00:00'` with `expirationAction: 'Log'`, and `keyExpirationPeriodInDays: 90`.

### LOW-12 — Only the blob endpoint has a private endpoint; five others have none

The account exposes `blob`, `dfs`, `file`, `queue`, `table` and `web`. Only `blob` has a private endpoint and matching private DNS zone.

Once CRITICAL-1 is fixed these become unreachable rather than dangerous — the correct outcome if nothing uses them. Until then they are five additional internet-facing surfaces. `dfs` needs its own group ID and its own `privatelink.dfs.core.windows.net` zone; it does not ride on blob private link. `isHnsEnabled` is null, so `dfs` is unlikely to be in use.

### LOW-13 — Standing subscription-scope Owner on a user principal

`owner@example.com` holds Owner at subscription scope, no condition, no description. For a personal sandbox this is ordinary and largely unavoidable. Recorded because Owner is the principal that can purge the Key Vault (MEDIUM-9) and grant further role assignments. The export cannot show whether this is permanent or PIM-eligible — `az role assignment list` returns active assignments either way.

### LOW-14 — Incomplete build, thin governance metadata

- `snet-app` is delegated to `Microsoft.Web/serverFarms` but no App Service plan or web app exists. A full /24 is reserved for a workload that is not there.
- The resource group carries `disposable: true` and `purpose: agent-pipeline-poc`, but no owner and no expiry. Every child resource has `{}` or `null` tags.
- `enableDdosProtection: false` is correct here — no public IPs, and DDoS Network Protection carries significant standing cost.

`disposable: true` with no expiry and no automation behind it is an intention, not a control; sandboxes tagged this way routinely survive for years.

---

## 3. Well-Architected notes

**Reliability.** `Standard_LRS` — three replicas in one datacentre, no zone or region redundancy. No RTO or RPO was stated, so this is a trade-off rather than a gap: LRS is the correct, cheapest choice for disposable sandbox data. Note the LRS→ZRS conversion path and geo-replication are partly create-time decisions, so a future requirement may mean a new account. Blob soft delete, versioning and point-in-time restore are not visible in the export.

**Security.** The weakest pillar and the source of every CRITICAL and HIGH finding. The building blocks are present — private endpoint, private DNS, RBAC-authorised vault, managed identity, TLS 1.2 minimum, `enableHttpsTrafficOnly: true`, `allowCrossTenantReplication: false` — but the perimeter is not closed (CRITICAL-1, HIGH-4), there is no segmentation (HIGH-5), the identity model is bypassed by account keys (HIGH-3), and the vault's audit trail does not exist (HIGH-6).

**Cost Optimization.** Appropriate. LRS, Hot tier, standard vault, no DDoS Network Protection, no gateways or firewalls. The genuine risk is lifecycle: a `disposable: true` group with no expiry or owner tag is how sandbox spend becomes permanent. Log Analytics SKU and retention are not in the export — left at default with growing volume, the workspace becomes the dominant line item.

**Operational Excellence.** The private DNS zone reports `numberOfRecordSets: 2` and one VNet link, consistent with correctly wired blob private link — the DNS plumbing is right. Against that: monitoring is partial (MEDIUM-10), the vault is unaudited (HIGH-6), and there is no evidence of IaC provenance, alert rules, action groups, or Azure Policy enforcing any of the above. `systemData` shows `createdByType: "User"` with a human UPN and `changedTime` values spread across a 20-minute window, consistent with interactive portal or CLI work rather than a single template deployment. If promoted, capture as IaC first — `devops-infrastructure-expert` for authoring, or `terraform-import` to bring these resources under Terraform state.

**Performance Efficiency.** No compute exists, so no scaling configuration to review and no throughput target stated. Forward-looking: when an App Service plan lands in `snet-app`, the first inelastic thing behind it is the subnet's address pool — 10.42.1.0/24 yields 251 usable addresses, and regional VNet integration consumes one per instance plus a reserve during scale and platform upgrades. At /24 that ceiling is comfortable and will not bind. The likelier ceilings, in order, are Key Vault's per-vault request throttling (per vault, not per caller, so every instance shares one budget — cache secrets at startup rather than fetching per request) and storage account request rate limits. Subnet size is create-time-immutable for practical purposes: it can only be resized while empty. Size it before the plan is deployed.

---

## 4. Open questions and assumptions

**Assumptions made.**

1. Non-production sandbox with no real or personal data, as stated. No SLA, RTO, RPO, throughput target or compliance scope was stated, and none has been assumed. Where a judgement depended on an unstated requirement — LRS vs ZRS, 7-day vs 90-day retention, infrastructure encryption, DDoS protection — it is recorded as a trade-off with its trigger condition rather than scored as a failure.
2. The resource group is the complete estate under review. The orphan delegated subnet (LOW-14) suggests a partial build, which would make that wrong.
3. The `09-diagnostic-settings.json` status convention was applied as briefed: `ok` authoritative, `unsupported` expected and not a gap. No row carried `failed`, so no finding rests on an unknown misread as a zero.

**Could not verify from this export.**

- Container access levels — required to confirm HIGH-2 is latent rather than live.
- Whether static website hosting is enabled (`$web` is public regardless of `allowBlobPublicAccess`).
- Blob service configuration: soft delete, versioning, point-in-time restore, lifecycle policies, and the blob-service diagnostic setting (MEDIUM-10).
- Log Analytics SKU, retention and daily cap.
- Role assignments scoped **below** the resource group. This particularly affects HIGH-3 and MEDIUM-8: if a data-plane role was granted at resource scope, effective permissions are wider than shown, not narrower.
- Whether the Owner assignment is PIM-eligible or permanently active (LOW-13).
- Network Watcher flow logs (VNet or NSG).
- Azure Policy assignments and Defender for Cloud plan coverage at subscription or management-group scope.

**Verification method.** The Microsoft Learn MCP tools were not reachable in this session. The four date-sensitive defaults underpinning HIGH-2, HIGH-3, MEDIUM-7 and MEDIUM-9 were verified by fetching the current Learn articles directly via WebFetch:

- *Configure anonymous read access for containers and blobs* (2026-08-20)
- *Prevent authorization with Shared Key* (2026-08-11)
- *Manage network policies for private endpoints* (2025-03-25)
- *Azure Key Vault soft-delete* (2026-04-10)

No other date-sensitive claim is asserted as fact without one of those sources behind it.
