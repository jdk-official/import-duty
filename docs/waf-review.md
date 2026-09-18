# Well-Architected review — `rg-agentpoc-8e9e55d7`

**Assessed:** 2026-09-18 · **Method:** static configuration review of a live
export, by construction · **Assessor:** `expert-agents:azure-architect` (opus),
findings independently re-verified against the raw export

> **This document judges. It does not describe.** What the estate *is* — its
> inferred purpose, network and identity design, and the three places it
> contradicts itself — is in [architecture.md](architecture.md).
>
> **Scope and limits.** This is a point-in-time review of *configuration*. It
> reports what the configuration **permits**, never what has happened. It is not
> a penetration test, not a tenant identity audit, and not a compliance
> certification. It stops at the resource-group boundary. §6 lists what could
> not be assessed.

---

## 1. Executive summary

Nine resources implementing a partially-built private web application platform.

**The building blocks of a sound design are present and the enforcement is not.**
A private endpoint fronts the storage account, but the storage firewall admits
every address on the internet, so the private path is additive rather than
exclusive. The Key Vault has no network restrictions at all. There are no network
security groups anywhere in the resource group. Separately, the workload identity
holds broad control-plane rights and no data-plane rights, which means its only
route to data is a shared account key — defeating the keyless design it was
evidently created to implement.

**Verdict: not fit to hold anything beyond disposable test data.**

For a sandbox tagged `disposable=true` that is tolerable and cheap to correct.
The concern is propagation: proof-of-concept shapes get copied into real
environments, and three of these findings are template-level defects rather than
one-off mistakes.

**One decision is already closed.** The Key Vault's 7-day soft-delete retention
can only be set at creation. It cannot be lengthened on this vault.

---

## 2. Pillar assessment

| Pillar | Position |
|---|---|
| **Security** | **Weakest.** Source of every CRITICAL and HIGH finding. Good primitives, no enforcement. |
| **Operational Excellence** | **Partial.** Correct DNS plumbing; the highest-value resource is unaudited; no IaC provenance, alerting or policy. |
| **Reliability** | **Trade-off, not a gap.** Single region, `Standard_LRS`, no zone redundancy — correct for disposable data. No SLA, RTO or RPO was stated, so there is no target to fail against. |
| **Cost Optimization** | **Appropriate.** LRS, Hot tier, standard vault, no DDoS Network Protection, no gateways. The real risk is lifecycle, not rate. |
| **Performance Efficiency** | **Not assessable.** No compute exists and no throughput target was stated. |

Recording Reliability and Cost as *trade-offs against unstated requirements*
rather than scoring them is deliberate. Marking a sandbox down for lacking
geo-redundancy nobody asked for produces a longer report and a less useful one.

---

## 3. Findings

Severity reflects the finding in its stated context — a disposable sandbox with
no real data. In production, several would rank higher.

### CRITICAL

**C-1 · Storage account reachable from the public internet; the private endpoint is decorative**
*Security*

`publicNetworkAccess: Enabled` with `networkRuleSet.defaultAction: Allow`, empty
`ipRules`, empty `virtualNetworkRules`, alongside an approved blob private
endpoint.

`defaultAction: Allow` admits every source address on the internet. The private
endpoint creates an additional private path; it does not close the public one.
Every control that depends on network isolation — the private DNS zone, the PE
subnet, the VNet link — is currently providing assurance it cannot deliver. This
is why it outranks the anonymous-access finding below: it makes every other
network control in the resource group ineffective.

**Remediation.** `publicNetworkAccess: 'Disabled'`, `networkAcls.defaultAction:
'Deny'`, `bypass: 'None'`.
**Sequencing is load-bearing:** confirm the deploying identity reaches the
account over the private endpoint first, or add a temporary `ipRules` entry for
the operator's egress address. Flip this blind and you lock yourself out of the
data plane.

---

### HIGH

**H-1 · Shared Key authorization is live, and the Contributor grant reaches the keys**
*Security*

`allowSharedKeyAccess` is unset. Microsoft documents this as permitting Shared
Key: the property returns no value until explicitly set, and the account accepts
key-authorized requests when it is null or true.

Separately the managed identity holds Contributor at resource-group scope, which
includes `storageAccounts/listkeys/action`, and holds **no** data-plane role.

These compose into a control bypass. The identity's only path to blob data is to
fetch the account key. That access is authorised as the account, not the
identity — it ignores RBAC scoping, is indistinguishable in logs from any other
key holder, and cannot be brought under Conditional Access.

**Remediation.** `allowSharedKeyAccess: false`, `defaultToOAuthAuthentication:
true`, plus a resource-scoped data-plane role (Storage Blob Data Contributor on
the account, not the resource group). This one change fixes both halves.

**H-2 · Anonymous blob access permitted at account level**
*Security*

`allowBlobPublicAccess: true`, set explicitly — current defaults are `false`.

The account flag alone does not expose data; a container's access level must
also be `Blob` or `Container`. So this is a precondition, not a live exposure.
But anonymous, unauthenticated, unlogged public read is one container-ACL change
away, available to anyone with write access to a container.

*Since this review, the export was extended: the account currently has **zero
containers**, confirmed by a successful query rather than assumed. The exposure
is latent, not live.*

**Remediation.** `allowBlobPublicAccess: false`, backed by the built-in policy
*Storage accounts should prevent anonymous access* in Deny mode.

**H-3 · Key Vault accepts traffic from the public internet**
*Security*

`publicNetworkAccess: Enabled`, `networkAcls: null`, no private endpoint, and no
`privatelink.vaultcore.azure.net` zone in the resource group.

`networkAcls: null` means no firewall at all. A workload in `snet-app` would
reach the vault over its public endpoint while reaching storage privately — see
[architecture.md §6.2](architecture.md). The half of the private-networking
design that was skipped is the half holding credentials.

**Remediation.** Mirror the blob pattern: private endpoint with group ID
`vault`, matching private DNS zone, VNet link, then `publicNetworkAccess:
'Disabled'` and `networkAcls.defaultAction: 'Deny'`.

**H-4 · No network security groups exist anywhere**
*Security*

`04-nsgs.json` is empty. Neither subnet has an NSG.

Without one, Azure's defaults permit all inbound within the VNet and all
outbound to the internet. There is no default-deny anywhere. The specific risk
is free lateral movement between `snet-app` and `snet-pe`: a compromised
application instance reaches the storage private endpoint with nothing in the
path to stop or record it.

**Remediation.** One NSG per subnet, explicit deny-all inbound at low priority
beneath what the workload needs.
**Coupled with M-1 — read them together.**

**H-5 · Key Vault has no diagnostic settings; secret access is unlogged**
*Operational Excellence*

Confirmed authoritative: the vault was queried successfully and has none.

`AuditEvent` is the only record of who read which secret, key or certificate and
when. Without it there is no way to answer "was this accessed?" after an
incident, and no way to detect anomalous retrieval during one. A Log Analytics
workspace already exists in the same resource group.

**Remediation.** Diagnostic setting with `categoryGroup: 'audit'` and
`'allLogs'` to the existing workspace. Prefer `categoryGroup` over enumerating
categories so new ones are captured automatically.

---

### MEDIUM

**M-1 · Private endpoint network policies disabled on `snet-pe`**
*Security*

`privateEndpointNetworkPolicies: Disabled` — the platform default, not a
regression. Recorded because it is a **trap for H-4**: attach an NSG to
`snet-pe` while this stays disabled and you get a control that appears
configured in the portal and silently does not filter private-endpoint traffic.
The same applies to any UDR intended to force PE traffic through a firewall.

**Remediation.** Set `privateEndpointNetworkPolicies: 'Enabled'` **in the same
change** as the NSG, never after.

**M-2 · Managed identity over-privileged on the control plane, under-privileged on the data plane**
*Security*

Contributor at resource-group scope lets the identity create, reconfigure and
delete every resource in the group — including deleting the Key Vault, rewriting
the storage firewall, or removing the private endpoint. Contributor cannot grant
role assignments, so this is not a direct escalation path to Owner; the risk is
destructive and lateral.

**Remediation.** Remove the RG-scoped Contributor. Replace with resource-scoped
roles matching the actual job. Fixing this also removes the mechanism in H-1.

**M-3 · Key Vault purge protection off, and the retention window is already immutable**
*Security / Reliability*

`enablePurgeProtection` unset, `softDeleteRetentionInDays: 7` against a default
of 90 — so 7 was chosen.

Without purge protection, anyone holding purge rights can permanently destroy
the vault or its contents immediately, with no recovery window. **The 7-day
retention cannot be lengthened on this vault**; changing it requires delete and
recreate, plus waiting out soft-delete before the name can be reused.

Most Azure services that integrate with Key Vault — Storage included — *require*
purge protection before using a vault-held key. If customer-managed keys are
ever wanted here, this vault cannot support them as built.

**Remediation.** For a disposable sandbox, 7 days is defensible — but record it
as a deliberate acceptance, not an oversight. Purge protection can still be
enabled in place, and is itself irreversible. If promoted beyond the sandbox,
recreate with 90 days.

**M-4 · Observability is partial**
*Operational Excellence*

Three gaps, all from successful queries:

- Storage has `logs: []` and only the `Transaction` metric — **no data-plane
  logs**. `StorageBlobLogs` comes from a diagnostic setting on the
  `blobServices/default` sub-resource, not the account. *Since extended, the
  export confirms that sub-resource has zero diagnostic settings.*
- The Log Analytics workspace has no diagnostic settings, so query activity
  against the security evidence store is itself unaudited.
- The VNet setting collects metrics but its only log category is disabled.

The storage gap also blocks the detection step Microsoft recommends *before*
disabling Shared Key (H-1): the documented query for key-authorized requests has
no data to run against, so you cannot measure what would break.

**Remediation.** Diagnostic setting on `blobServices/default` with
`StorageRead` / `StorageWrite` / `StorageDelete`; an `audit` setting on the
workspace; enable `Capacity` metrics.

**M-5 · No SAS expiry policy, no key rotation policy**
*Security*

`sasPolicy` and `keyPolicy` both unset; both account keys date from creation and
have never been rotated.

While Shared Key remains enabled, nothing bounds how long an issued SAS stays
valid — a ten-year token is a durable, unrevocable credential that appears in no
access review.

**Remediation.** Fixing H-1 makes both moot. If Shared Key must stay:
`sasExpirationPeriod: '0.08:00:00'` with `expirationAction: 'Log'`, and
`keyExpirationPeriodInDays: 90`.

---

### LOW

**L-1 · Only blob has a private endpoint** — `dfs`, `file`, `queue`, `table`
and `web` endpoints have none. Once C-1 is fixed these become unreachable rather
than dangerous, which is correct if unused. Note `dfs` needs its own group ID
and zone; it does not ride on blob private link.

**L-2 · Standing subscription-scope Owner on a user principal** — ordinary for a
personal sandbox. Recorded because Owner is the principal that can purge the
vault (M-3). The export cannot show whether the assignment is PIM-eligible.

**L-3 · Thin governance metadata** — the group is tagged `disposable=true` with
no owner and no expiry, and every child resource is untagged. An intention, not
a control; sandboxes tagged this way routinely survive for years.

---

## 4. Create-time-immutable decisions

Not findings — **deadlines**. Once deployed, the remedy is a rebuild.

| Resource | Property | Current | Window |
|---|---|---|---|
| Key Vault | `softDeleteRetentionInDays` | `7` | **Closed.** Already deployed. |
| Storage | `requireInfrastructureEncryption` | unset | **Closed.** |
| Storage | replication SKU | `Standard_LRS` | Constrained; some conversions need a new account. |
| `snet-pe` | `addressPrefix` | `10.42.2.0/24` | **Closed** — occupied by the private endpoint. |
| `snet-app` | `addressPrefix` | `10.42.1.0/24` | **OPEN** — empty, so still resizable. Closes on first use. |

`snet-app` is the only one still open, and it closes the moment compute lands.

---

## 5. Remediation plan

Ordered by dependency, not by severity. Several fixes are coupled, and doing
them in the wrong order produces either an outage or a control that silently
does nothing.

| # | Action | Why here |
|---|---|---|
| 1 | Add the blob-service diagnostic setting (M-4) | Must precede step 3 — you cannot measure what disabling Shared Key would break without these logs |
| 2 | Add the Key Vault diagnostic setting (H-5) | Independent, zero risk, restores the audit trail |
| 3 | Grant a resource-scoped data-plane role; remove RG Contributor (M-2) | Must precede step 4 — the identity needs a working non-key path first |
| 4 | `allowSharedKeyAccess: false` (H-1) | Safe only after 1 and 3 |
| 5 | `allowBlobPublicAccess: false` (H-2) | Independent; verify no container is public first |
| 6 | Prove private-path reachability, then close storage public access (C-1) | Highest severity, deliberately not first — done blind it locks you out |
| 7 | Key Vault private endpoint + DNS zone, then close its public access (H-3) | Mirrors step 6 |
| 8 | NSGs **and** `privateEndpointNetworkPolicies: Enabled` together (H-4, M-1) | One change. An NSG alone on `snet-pe` does nothing |
| 9 | Size `snet-app` deliberately | Before compute lands, or the window closes |
| 10 | Purge protection, SAS and key policies, tagging (M-3, M-5, L-3) | Hardening once the above holds |

**C-1 is the highest-severity finding and it is sixth.** That is not a
de-prioritisation — it is the only safe position for it.

---

## 6. What could not be assessed

Carried forward honestly. Three items from the original review have since been
closed by extending the export; the rest remain open.

**Closed since the review**

- Container access levels — queried successfully: **zero containers**, so H-2 is
  latent rather than live.
- `blobServices/default` diagnostic settings — **zero**, confirming M-4.
- Role assignments scoped **below** the resource group — **none**, so no
  principal has wider effective permissions than this review shows. This was the
  one unknown that could have widened the findings.

**Still open**

- Whether static website hosting is enabled (`$web` is public regardless of
  `allowBlobPublicAccess`, and a `web` endpoint is present).
- Blob soft delete, versioning, point-in-time restore, lifecycle policies.
- Log Analytics SKU, retention and daily cap — bears on cost and on how long
  security evidence survives.
- Whether the subscription Owner assignment is PIM-eligible or permanent.
- Network Watcher flow logs.
- Azure Policy assignments and Defender for Cloud coverage at subscription or
  management-group scope — several remediations above recommend policy
  enforcement, and existing assignments may already provide some.

**Method note.** The Microsoft Learn MCP tools were not reachable during the
review. Four date-sensitive defaults — anonymous-access semantics, the Shared
Key null default, private-endpoint network policies, and Key Vault purge
protection — were verified by fetching the current Learn articles directly, and
each finding that rests on one names its source and publication date. No other
date-sensitive claim is asserted as fact.
