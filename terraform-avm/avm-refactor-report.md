# AVM refactor report — import-duty-work/avm

## Method note (read this first)

There is no state file and no credentials available in this working directory, and the
task boundary forbids `terraform apply`/live `az` calls. Equivalence below is therefore
**static reasoning**, not a live plan diff:

- `terraform init` and `terraform validate` were run against the refactored
  configuration and pass (one informational deprecation warning, noted below).
- Every AVM module's `main.tf`, `variables.tf`, `outputs.tf` and `terraform.tf` were
  fetched from GitHub at the exact pinned tag and read directly (not from memory or the
  README) to compare the underlying resource type, its default values, and the
  provider/version it depends on, against the original raw `azurerm_*` block.
- `moved` blocks are used everywhere a resource crosses into a module, on the basis that
  the underlying resource **type** is unchanged (confirmed from each module's `main.tf`).
  Terraform accepts `moved` blocks between a root-module resource and the same resource
  type nested in a child module; this is the documented pattern for "move a resource into
  a module" refactors.
- **A live plan would still need to confirm**: (1) that `moved` blocks apply cleanly
  against the real state file with no drift outside what's listed here, (2) the exact
  values Azure currently holds for every attribute this pass left at the AVM module's
  default (e.g. that the deployed KV really has no network ACLs, that the deployed LAW
  really has internet ingestion/query enabled — both assumed true from the original
  config, not re-verified against the live resource), and (3) that no other resource
  outside this configuration references the moved resources' addresses (e.g. state in
  other workspaces, ARM template outputs).

## Mapping table

| Resource (original address) | Outcome | AVM module @ version |
|---|---|---|
| `azurerm_resource_group.this` | **Raw — poor fit** | n/a — `Azure/avm-res-resources-resourcegroup/azurerm` (0.4.0) exists but implements the RG as `azapi_resource`, not `azurerm_resource_group` |
| `azurerm_virtual_network.this` | **Raw — poor fit** | n/a — `Azure/avm-res-network-virtualnetwork/azurerm` (0.22.2) implements the vnet (and its subnets) as `azapi_resource` |
| `azurerm_subnet.app` | **Raw** (tied to vnet decision) | same as above |
| `azurerm_subnet.pe` | **Raw** (tied to vnet decision) | same as above |
| `azurerm_storage_account.this` | **Raw — poor fit** | n/a — `Azure/avm-res-storage-storageaccount/azurerm` (0.10.0) implements the account as `azapi_resource` |
| `azurerm_storage_account_queue_properties.this` | **Raw** (tied to storage account decision) | n/a |
| `azurerm_private_dns_zone.blob` | **Raw — poor fit** | n/a — `Azure/avm-res-network-privatednszone/azurerm` (0.5.0) implements the zone as `azapi_resource` |
| `azurerm_private_dns_zone_virtual_network_link.blob` | **Raw** (tied to DNS zone decision) | n/a |
| `azurerm_private_dns_a_record.blob` | **Raw** (tied to DNS zone decision) | n/a |
| `azurerm_private_endpoint.blob` | **Moved to AVM** | `Azure/avm-res-network-privateendpoint/azurerm` **0.2.0** |
| `azurerm_key_vault.this` | **Moved to AVM** | `Azure/avm-res-keyvault-vault/azurerm` **0.11.0** |
| `azurerm_log_analytics_workspace.this` | **Moved to AVM** | `Azure/avm-res-operationalinsights-workspace/azurerm` **0.5.1** |
| `azurerm_user_assigned_identity.this` | **Moved to AVM** | `Azure/avm-res-managedidentity-userassignedidentity/azurerm` **0.5.2** |
| `azurerm_role_assignment.contributor` | **Moved to AVM** (folded into the UAI module's `role_assignments` input) | same module as above |
| `azurerm_monitor_diagnostic_setting.vnet` | **Raw** — no standalone AVM module for diagnostic settings; target (vnet) also stays raw | n/a |
| `azurerm_monitor_diagnostic_setting.storage` | **Raw** — same reason; target (storage account) also stays raw | n/a |

**Total: 5 of 16 resources moved onto AVM modules (4 module calls); 11 stay raw.**

## Why the four "poor fit" modules were rejected

Fetching each module's `main.tf` (not just its listing on the registry) showed that
`avm-res-resources-resourcegroup`, `avm-res-network-virtualnetwork`,
`avm-res-storage-storageaccount`, and `avm-res-network-privatednszone` have all migrated
their core resource to the `azapi` provider (`resource "azapi_resource"`) instead of the
matching `azurerm_*` resource. A `moved` block requires the source and destination to be
the *same resource type* (mechanically, the same provider's schema); moving state from
`azurerm_resource_group` to `azapi_resource`, or `azurerm_virtual_network` to
`azapi_resource`, has no such path. Adopting these modules would therefore not be
refactor-with-`moved`, it would be destroy-and-recreate of the resource group, vnet (and
delegated subnet + PE subnet), storage account, and private DNS zone — i.e. the entire
estate — despite presenting as a like-for-like module swap. That fails the "same
deployment outcome" bar this task is gated on, so all four stay raw, and everything
downstream of them (subnets, queue properties, vnet link, A record) stays raw too since
there's nothing left to wrap once the parent is excluded.

This is worth flagging as a general caution: AVM's own module inventory is not a stable
signal of "will produce a clean `moved` diff" — some modules changed their underlying
resource type between major versions specifically to gain azapi's faster property
coverage, which is invisible unless you read `main.tf` rather than the variable/README
surface.

## Equivalence evidence

`terraform validate`: **passes** (Success, with one deprecation warning — see below).
`terraform init`: succeeds; the four adopted modules pull in `azapi`, `modtm`, `random`,
and `time` as transitive provider requirements (used internally for optional features
this config doesn't exercise, e.g. customer-managed-key rotation, telemetry, private-DNS
auto-linking) — Terraform resolved these automatically with no explicit `provider {}`
blocks needed for them.

Per group, the accepted/explained diffs a live plan should show:

### Group: Private endpoint → `avm-res-network-privateendpoint` 0.2.0
- **(a) representation-only**: `moved` block relocates
  `azurerm_private_endpoint.blob` → `module.private_endpoint_blob.azurerm_private_endpoint.this`.
  All arguments (`is_manual_connection = false`, connection name `conn-blob`,
  `subresource_names = ["blob"]`, DNS zone group name `zg-blob` and zone ID) are wired
  explicitly to match the original; `network_interface_name` is explicitly passed as
  `null` so Azure keeps auto-generating the NIC name as it did originally, rather than
  the module's `custom_network_interface_name` argument introducing a name Azure never
  had. No behavioural difference.

### Group: Identity + role assignment → `avm-res-managedidentity-userassignedidentity` 0.5.2
- **(a) representation-only**: two `moved` blocks — the identity itself, and the
  Contributor role assignment (now `module.user_assigned_identity.azurerm_role_assignment.this["contributor"]`,
  folded into the module's own `role_assignments` map rather than a sibling resource).
  Same scope (`azurerm_resource_group.this.id`), same role definition ID, same principal
  (the module always assigns to its own identity's `principal_id` — confirmed from its
  `main.tf`). No behavioural difference.

### Group: Key Vault → `avm-res-keyvault-vault` 0.11.0
- **(a) representation-only**: `moved` block relocates `azurerm_key_vault.this`.
- **(b) AVM-enforced defaults, all explicitly overridden to hold the original posture,
  and all surfaced here per the task's instruction not to silently change deployed
  posture**:
  - `network_acls` — module default is `{ bypass = "None", default_action = "Deny" }`
    when the variable is left at its default `{}`. The original vault has **no** network
    ACL block at all (open — the provider's implicit default, matching the estate's
    known weak posture). **Overridden to `network_acls = null`** to hold the original
    behaviour. *Available if wanted*: setting this would network-lock the vault, which
    pairs naturally with the storage account's private endpoint already in place.
  - `purge_protection_enabled` — module default is `true`; the attribute is **irreversible
    once enabled** (Azure will not let it be turned back off). Original vault has it
    unset (provider default `false`). **Overridden to `false`** to hold original
    behaviour — deliberately not defaulted on, since enabling it live can't be undone by
    a later refactor pass.
  - `legacy_access_policies_enabled` — module default `false` flips
    `rbac_authorization_enabled` to `true`. This is not just a hardening knob: it changes
    the **data-plane access model** for secrets/keys from vault access policies to Azure
    RBAC, which would break any existing access-policy grants outright. Original vault
    has RBAC authorization off (provider default when unset). **Overridden to
    `legacy_access_policies_enabled = true`** to hold original behaviour.
  - `public_network_access_enabled` — module default `true` already matches the
    original's implicit default; set explicitly for documentation, not a behavioural
    change.

### Group: Log Analytics Workspace → `avm-res-operationalinsights-workspace` 0.5.1
- **(a) representation-only**: `moved` block relocates `azurerm_log_analytics_workspace.this`.
- **(b) AVM-enforced defaults, explicitly overridden**:
  - `log_analytics_workspace_internet_ingestion_enabled` and
    `..._internet_query_enabled` — module defaults are `"false"`/`"false"` (public
    internet ingestion/query disabled). The original workspace has neither attribute set,
    so the azurerm provider default applies, which is `true`/`true`. **Overridden to
    `"true"`/`"true"`** to hold original behaviour. *Available if wanted*: this is a real
    hardening opportunity worth a deliberate follow-up, not bundled here.
  - `log_analytics_workspace_local_authentication_enabled = true` matches the original's
    explicit setting; passed for parity, no behavioural change.
- **Informational, not a behavioural diff**: `terraform validate` emits a deprecation
  warning from inside the module's own `outputs.tf` — its `resource` output surfaces the
  provider-deprecated `local_authentication_disabled` computed attribute. This originates
  in the module source, not in this configuration, and does not affect the deployed
  resource (`local_authentication_enabled` is the attribute actually set).

### Groups that remain fully raw (vnet, storage, resource group, private DNS, diagnostic settings)
No AVM module was applied, so no diff to evaluate — these blocks are byte-identical to
the original except for two `target_resource_id`/`log_analytics_workspace_id` references
in the diagnostic settings, which now point at `module.log_analytics_workspace.resource_id`
instead of `azurerm_log_analytics_workspace.this.id`. Both resolve to the same LAW
resource ID post-move, so this is **(a) representation-only**.

### Cross-cutting: provider version bump
`Azure/avm-res-keyvault-vault` 0.11.0 requires `azurerm >= 4.81, < 5.1`; the original
config pinned an exact `azurerm = "4.80.0"`. **Bumped the constraint to
`>= 4.81.0, < 5.0.0`** (still v4, no major version change) — this is a version change AVM
forces, surfaced here per the task boundary rather than applied silently. `terraform init`
resolved `4.81.0`, the latest available v4 release at time of writing.

### Cross-cutting: AVM telemetry resources
Every adopted AVM module can create a lightweight telemetry marker resource (via the
`modtm`/`azapi` providers) unless `enable_telemetry = false`. Set to `false` on all four
module calls so the plan reflects only the real Azure estate and isn't cluttered with
resources that have no bearing on deployment equivalence.

## Residual list (no AVM coverage, or poor fit — left untouched)

| Resource | Reason | Closest module |
|---|---|---|
| `azurerm_resource_group.this` | Module implemented via `azapi_resource`; would force replacement | `Azure/avm-res-resources-resourcegroup/azurerm` 0.4.0 (rejected) |
| `azurerm_virtual_network.this`, `azurerm_subnet.app`, `azurerm_subnet.pe` | Module implemented via `azapi_resource`; would force replacement of vnet + subnets + delegation | `Azure/avm-res-network-virtualnetwork/azurerm` 0.22.2 (rejected) |
| `azurerm_storage_account.this`, `azurerm_storage_account_queue_properties.this` | Module implemented via `azapi_resource`; would force replacement (data-loss risk on a real account) | `Azure/avm-res-storage-storageaccount/azurerm` 0.10.0 (rejected) |
| `azurerm_private_dns_zone.blob`, `..._virtual_network_link.blob`, `..._a_record.blob` | Module implemented via `azapi_resource`; would force replacement, and depends on the raw vnet anyway | `Azure/avm-res-network-privatednszone/azurerm` 0.5.0 (rejected) |
| `azurerm_monitor_diagnostic_setting.vnet`, `.storage` | No standalone AVM module for diagnostic settings — they're a `diagnostic_settings` input on each resource module; targets stay raw regardless | n/a |

## Follow-ups

- **Version bump AVM will eventually force further**: `avm-res-keyvault-vault` already
  requires `azurerm >= 4.81`; watch its next minor for further lower-bound creep as it's
  the tightest constraint among the four adopted modules.
- **Deliberate hardening now available, not adopted this pass** (all three require a
  decision, not a default):
  - Key Vault `network_acls` — could default-deny public network access now that a
    private endpoint already exists for blob storage; a similar endpoint would be needed
    for the vault's data plane first.
  - Key Vault `purge_protection_enabled` — irreversible; worth enabling deliberately once
    the estate is past its POC/disposable stage (see the RG's own `disposable = "true"`
    tag), not before.
  - Log Analytics Workspace `internet_ingestion_enabled`/`internet_query_enabled` — could
    be locked to `false` if AMPLS/private link is later added for the workspace.
- **AVM features now available that the old code lacked**: the KV, LAW, UAI and PE
  modules all expose `lock` (resource-lock) and `diagnostic_settings` inputs directly;
  wiring the two existing diagnostic settings through the LAW/KV modules' own interface
  in a later pass (once the vnet/storage decision above is revisited) would remove the
  two standalone `azurerm_monitor_diagnostic_setting` resources.
- **Revisit the four rejected modules if AVM ever ships an `azurerm`-backed alternative**
  for resource group, vnet, storage account, or private DNS zone — re-check their
  `main.tf` before assuming the azapi migration is permanent.
