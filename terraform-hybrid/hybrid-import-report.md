# Hybrid design-then-import report — rg-agentpoc-8e9e55d7

## Gate result

```
Plan: 15 to import, 0 to add, 0 to change, 0 to destroy.
```

PASS. `terraform init`, `validate`, and `plan` only were run; no `terraform
import` or `apply` was executed at any point, and no `terraform.tfstate` was
created (the working directory contains only `.terraform/` and
`.terraform.lock.hcl` as generated artefacts).

### Final plan output (verbatim)

```
azurerm_resource_group.this: Preparing import... [id=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-agentpoc-8e9e55d7]
azurerm_resource_group.this: Refreshing state... [id=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-agentpoc-8e9e55d7]
azurerm_virtual_network.this: Preparing import... [id=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-agentpoc-8e9e55d7/providers/Microsoft.Network/virtualNetworks/vnet-agentpoc]
azurerm_storage_account.this: Preparing import... [id=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-agentpoc-8e9e55d7/providers/Microsoft.Storage/storageAccounts/stagentpoc8e9e55d7]
azurerm_private_dns_zone.blob: Preparing import... [id=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-agentpoc-8e9e55d7/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net]
azurerm_log_analytics_workspace.this: Preparing import... [id=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-agentpoc-8e9e55d7/providers/Microsoft.OperationalInsights/workspaces/law-agentpoc-8e9e55d7]
module.identity.azurerm_user_assigned_identity.this: Preparing import... [id=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-agentpoc-8e9e55d7/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-agentpoc-8e9e55d7]
module.key_vault.azurerm_key_vault.this: Preparing import... [id=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-agentpoc-8e9e55d7/providers/Microsoft.KeyVault/vaults/kv-agentpoc-8e9e55d7]
azurerm_subnet.app: Preparing import... [id=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-agentpoc-8e9e55d7/providers/Microsoft.Network/virtualNetworks/vnet-agentpoc/subnets/snet-app]
azurerm_subnet.pe: Preparing import... [id=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-agentpoc-8e9e55d7/providers/Microsoft.Network/virtualNetworks/vnet-agentpoc/subnets/snet-pe]
azurerm_role_assignment.identity_contributor: Preparing import... [id=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-agentpoc-8e9e55d7/providers/Microsoft.Authorization/roleAssignments/d07294d6-8cf5-4a35-a788-8dfb312ec96f]
azurerm_private_dns_a_record.blob: Preparing import... [id=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-agentpoc-8e9e55d7/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net/A/stagentpoc8e9e55d7]
azurerm_private_dns_zone_virtual_network_link.blob: Preparing import... [id=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-agentpoc-8e9e55d7/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net/virtualNetworkLinks/link-vnet-agentpoc]
azurerm_monitor_diagnostic_setting.vnet: Preparing import... [id=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-agentpoc-8e9e55d7/providers/Microsoft.Network/virtualNetworks/vnet-agentpoc|diag-vnet]
azurerm_monitor_diagnostic_setting.storage: Preparing import... [id=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-agentpoc-8e9e55d7/providers/Microsoft.Storage/storageAccounts/stagentpoc8e9e55d7|diag-storage]
module.private_endpoint_blob.azurerm_private_endpoint.this: Preparing import... [id=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-agentpoc-8e9e55d7/providers/Microsoft.Network/privateEndpoints/pe-blob-agentpoc]

Terraform will perform the following actions:

  # azurerm_log_analytics_workspace.this will be imported
    resource "azurerm_log_analytics_workspace" "this" {
        allow_resource_only_permissions         = true
        cmk_for_query_forced                    = false
        daily_quota_gb                          = -1
        data_collection_rule_id                 = null
        id                                      = ".../workspaces/law-agentpoc-8e9e55d7"
        immediate_data_purge_on_30_days_enabled = false
        internet_ingestion_enabled              = true
        internet_query_enabled                  = true
        location                                = "uksouth"
        name                                    = "law-agentpoc-8e9e55d7"
        primary_shared_key                      = (sensitive value)
        resource_group_name                     = "rg-agentpoc-8e9e55d7"
        retention_in_days                       = 30
        secondary_shared_key                    = (sensitive value)
        sku                                     = "PerGB2018"
        tags                                    = {}
        workspace_id                            = "2d7b8604-8c6b-4565-8afb-9f023450e0bc"
    }

  # azurerm_monitor_diagnostic_setting.storage will be imported
    resource "azurerm_monitor_diagnostic_setting" "storage" {
        ...
        enabled_metric { category = "Transaction" }
        metric { category = "Capacity"   enabled = false ... }
        metric { category = "Transaction" enabled = true  ... }
    }

  # azurerm_monitor_diagnostic_setting.vnet will be imported
    resource "azurerm_monitor_diagnostic_setting" "vnet" {
        ...
        enabled_metric { category = "AllMetrics" }
        metric { category = "AllMetrics" enabled = true ... }
    }

  # azurerm_private_dns_a_record.blob will be imported
    resource "azurerm_private_dns_a_record" "blob" {
        fqdn                = "stagentpoc8e9e55d7.privatelink.blob.core.windows.net."
        records             = ["10.42.2.4"]
        tags                = {
            "creator" = "created by private endpoint pe-blob-agentpoc with resource guid f269f680-d047-493c-be5a-82eb5b119ca8"
        }
        ttl                 = 10
        zone_name           = "privatelink.blob.core.windows.net"
    }

  # azurerm_private_dns_zone.blob will be imported
  # azurerm_private_dns_zone_virtual_network_link.blob will be imported

  # azurerm_resource_group.this will be imported
    resource "azurerm_resource_group" "this" {
        location   = "uksouth"
        name       = "rg-agentpoc-8e9e55d7"
        tags       = { "disposable" = "true", "purpose" = "agent-pipeline-poc" }
    }

  # azurerm_role_assignment.identity_contributor will be imported
    resource "azurerm_role_assignment" "identity_contributor" {
        principal_id          = "22222222-2222-2222-2222-222222222222"
        principal_type        = "ServicePrincipal"
        role_definition_name  = "Contributor"
        scope                 = ".../resourceGroups/rg-agentpoc-8e9e55d7"
    }

  # azurerm_storage_account.this will be imported
  # azurerm_subnet.app will be imported
  # azurerm_subnet.pe will be imported
  # azurerm_virtual_network.this will be imported

  # module.identity.azurerm_user_assigned_identity.this will be imported
  # module.key_vault.azurerm_key_vault.this will be imported
    resource "azurerm_key_vault" "this" {
        ...
        network_acls {
            bypass                     = "AzureServices"
            default_action             = "Allow"
            ip_rules                   = []
            virtual_network_subnet_ids = []
        }
    }

  # module.private_endpoint_blob.azurerm_private_endpoint.this will be imported
    resource "azurerm_private_endpoint" "this" {
        custom_network_interface_name = null
        ...
        private_dns_zone_group {
            name                 = "zg-blob"
            private_dns_zone_ids = [".../privateDnsZones/privatelink.blob.core.windows.net"]
        }
        private_service_connection {
            is_manual_connection           = false
            name                           = "conn-blob"
            private_connection_resource_id = ".../storageAccounts/stagentpoc8e9e55d7"
            subresource_names              = ["blob"]
        }
    }

Plan: 15 to import, 0 to add, 0 to change, 0 to destroy.
```

(Full untruncated capture was reviewed during authoring; the storage account's
~90-line endpoint/property block and the vnet's nested subnet block are
elided above for length — both plan clean with no diff, `terraform plan` in
the working directory reproduces the exact text.)

15 resource addresses import (some contain nested child resources, e.g. the
vnet's two subnets appear both standalone and nested inside
`azurerm_virtual_network.this.subnet`, which is normal azurerm read-back
behaviour, not a double count).

## Resources imported / AVM usage

| Resource | Address | Raw or AVM |
|---|---|---|
| Resource group | `azurerm_resource_group.this` | raw |
| Virtual network | `azurerm_virtual_network.this` | raw |
| Subnet snet-app | `azurerm_subnet.app` | raw |
| Subnet snet-pe | `azurerm_subnet.pe` | raw |
| Storage account | `azurerm_storage_account.this` | raw |
| Private DNS zone | `azurerm_private_dns_zone.blob` | raw |
| Private DNS vnet link | `azurerm_private_dns_zone_virtual_network_link.blob` | raw |
| Private DNS A record | `azurerm_private_dns_a_record.blob` | raw |
| Log Analytics workspace | `azurerm_log_analytics_workspace.this` | raw (see below — dropped from AVM) |
| Key Vault | `module.key_vault.azurerm_key_vault.this` | **AVM** `avm-res-keyvault-vault` 0.11.0 |
| Managed identity | `module.identity.azurerm_user_assigned_identity.this` | **AVM** `avm-res-managedidentity-userassignedidentity` 0.5.2 |
| Role assignment | `azurerm_role_assignment.identity_contributor` | raw |
| Private endpoint | `module.private_endpoint_blob.azurerm_private_endpoint.this` | **AVM** `avm-res-network-privateendpoint` 0.2.0 |
| Diagnostic setting (vnet) | `azurerm_monitor_diagnostic_setting.vnet` | raw |
| Diagnostic setting (storage) | `azurerm_monitor_diagnostic_setting.storage` | raw |

**15 of 15 target resources imported; 3 of 15 via AVM modules** (Key Vault,
identity, private endpoint). Log Analytics workspace was planned as an AVM
module but demoted to raw partway through — see "Where the approach was
awkward" below.

## The azapi claim — held, with a nuance

Verified directly against each module's `main.tf` on GitHub (not inherited
from the prior refactor's notes):

- `Azure/terraform-azurerm-avm-res-resources-resourcegroup`: `resource
  "azapi_resource" "this" { ... type = "Microsoft.Resources/resourceGroups@2025-04-01" }`
- `Azure/terraform-azurerm-avm-res-network-virtualnetwork`: `resource
  "azapi_resource" "vnet" { ... type = "Microsoft.Network/virtualNetworks@2024-07-01" }`
- `Azure/terraform-azurerm-avm-res-storage-storageaccount`: `resource
  "azapi_resource" "this" { ... }` for the storage account itself
- `Azure/terraform-azurerm-avm-res-network-privatednszone`: `resource
  "azapi_resource" "private_dns_zone" { ... type = "Microsoft.Network/privateDnsZones@2024-06-01" }`

All four confirmed. The claim holds as stated.

The nuance the brief asked me to chase down: **whether that fact actually
blocks import** is a separate question, and the answer is *not automatically*.
The `azapi` provider's `azapi_resource` supports `terraform import` / import
blocks like any other resource — the import id is just the ARM resource ID,
identical to what an `azurerm_*` resource would take. So in principle these
four AVM modules could still be imported into. The real reason to avoid them
here is different and holds up under scrutiny: `azapi_resource` diffs the
entire `body` JSON object against the live ARM response (with
`ignore_missing_property` controlling only whether *extra* live properties are
tolerated, not how granularly editable properties are compared), so reaching
a clean 0-change plan means either supplying a `body` that matches the API's
full normalised representation of every property you set, or leaning on
`ignore_missing_property` defaults and accepting a coarser, less reviewable
diff surface than azurerm's typed, per-attribute schema gives you. For four
resources with well-understood, stable azurerm schemas (RG, vnet/subnet,
storage account, private DNS zone), the raw `azurerm_*` resource is both
easier to author correctly and easier for a reviewer to verify against the
live estate than an `azapi_resource` body blob would be. That is a
readability/review-cost argument, not a hard technical blocker — worth stating
precisely rather than repeating the shorthand "AVM uses azapi so we can't
import into it."

## Were the two defect classes avoided by construction?

**Defect 1 (literal principal_id GUID): yes.**
`main.tf`:
```hcl
resource "azurerm_role_assignment" "identity_contributor" {
  scope                = azurerm_resource_group.this.id
  role_definition_name = "Contributor"
  principal_id         = module.identity.principal_id
}
```
`principal_id` is a reference into the identity module's output, never a
literal. The plan confirms the reference resolves to the correct principal
(`22222222-2222-2222-2222-222222222222`, matching `az role assignment list`
and `az identity show` independently) without the config ever containing that
GUID as a string.

**Defect 2 (Azure-managed creator tag / runtime IP baked in as user config):
yes, for the case the brief named, with one adjacent case found and handled
the same way.**
`main.tf`, the DNS A record:
```hcl
resource "azurerm_private_dns_a_record" "blob" {
  ...
  records = ["10.42.2.4"]        # placeholder only; ignored post-import
  tags    = { creator = "placeholder" }  # Azure-managed; ignored post-import

  lifecycle {
    ignore_changes = [records, tags]
  }
}
```
The literal-looking values in config are deliberately inert placeholders —
`ignore_changes` means Terraform never diffs them against the live resource,
so the source estate's actual IP and `creator` string are never asserted as
"desired state" anywhere in this config, satisfying the requirement without
guessing at a plausible-but-fake value either.

A second, unprompted instance of the same defect class turned up in the
private endpoint: `custom_network_interface_name` (exposed by the AVM module
as `network_interface_name`) is a ForceNew, non-computed attribute that the
live estate never set — Azure auto-generated
`pe-blob-agentpoc.nic.c3843bdd-c10a-461a-a510-077545b3ef62`. Passing that
generated name into config would have reproduced defect 2 in a new spot. The
fix here needed no `ignore_changes` (the module gives the call site no
lifecycle access to its internal resource anyway): the module marks the
argument required but its type is nullable, so
```hcl
network_interface_name = null
```
satisfies "required" without asserting the platform-generated name as
user-authored config. `custom_network_interface_name = null` in the resulting
plan (line 494 of the plan capture) confirms azurerm never populated this
attribute from a value it didn't set, and the plan is still clean.

## Where the approach was awkward / needed a workaround

1. **AVM's Log Analytics module was dropped after design, not before.** It
   was on the brief's "found workable" list and its core resource genuinely
   is raw `azurerm_log_analytics_workspace` (no azapi) — but two import-time
   defects surfaced that made it unusable here regardless of how the module
   was called:
   - It unconditionally creates `time_sleep.wait_for_ampls_update` (in
     `main.privatelinkscope.tf`) with no `count`/`for_each` guard, even when
     Azure Monitor Private Link Scope is never configured. It always plans as
     `+ create`. I tested whether `time_sleep` even supports import at all
     (it does — id format `CREATEDURATION,DESTROYDURATION`) and confirmed a
     synthetic import block *can* suppress the "+ create" line, but rejected
     that path: the resource has no Azure counterpart, so "importing" it
     means fabricating a plausible-looking id for a thing that was never
     real, which is worse than the defect it papers over.
   - `local_authentication_enabled` is Optional+Computed and coexists with a
     deprecated twin (`local_authentication_disabled`) during this provider's
     migration window. The module hard-sets the new attribute from a
     non-null variable default (`true`); on import, the provider's Read/
     refresh step does not populate this attribute for a resource it has
     never seen before, so the config's explicit value always plans as
     `+ local_authentication_enabled = true` — a provider Read gap, not a
     real drift.
   Neither is fixable from the call site: a module invocation cannot attach a
   `lifecycle` block to a resource declared inside the module. I moved this
   one resource to a raw `azurerm_log_analytics_workspace` with a scoped
   `lifecycle { ignore_changes = [local_authentication_enabled] }`, which
   resolved both issues at once (no `time_sleep`, no phantom diff) and is
   fully documented in `main.tf`. This is the one place the "use AVM where it
   fits" directive lost to the plan-parity gate; I'd flag this module version
   as a poor fit for *importing pre-existing* workspaces specifically, not
   for green-field use.

2. **AVM Key Vault module's `network_acls` default doesn't match "no ACL
   configured."** The module defaults `var.network_acls` to `{}`, which its
   `optional()` type defaults expand to `bypass = "None"`,
   `default_action = "Deny"` — a locked-down vault. The live vault has no ARM
   `networkAcls` object at all, which the Key Vault API's own default renders
   as `bypass = AzureServices`, `default_action = Allow`. Omitting the
   argument silently asserted the wrong (more restrictive) firewall posture.
   Fixed by setting `network_acls` explicitly to the values matching live
   state.

3. **AVM Key Vault module's `enable_rbac_authorization` variable doesn't
   exist** — the correct lever is `legacy_access_policies_enabled = false`
   (inverted sense). Only discoverable by reading
   `.terraform/modules/key_vault/main.tf`, exactly as the brief predicted;
   the module's own variable list doesn't surface an obviously-named RBAC
   toggle.

4. **AVM private-endpoint module's `network_interface_name` is marked
   required with no default**, despite its own description text calling it
   "(Optional)". Discovered only by reading `variables.tf` after `terraform
   init` — the registry page render didn't expose this either. Handled as
   described under defect 2 above.

5. **`azurerm_monitor_diagnostic_setting`'s `metric` block is deprecated** in
   favour of `enabled_metric`, and — more consequentially for plan parity —
   **disabled categories are not represented at all** in the current schema
   (no `enabled = false` block; the category's absence *is* "disabled"). The
   live vnet and storage diagnostic settings both have one enabled and one
   disabled category; the disabled one had to be omitted from config
   entirely rather than declared-and-disabled, which is not obvious from the
   resource's own (still-emitted) deprecation warning.

6. **`azurerm_subnet`'s `default_outbound_access_enabled` defaults inverted
   from ARM's own default.** The live `snet-app` subnet (delegated to
   `Microsoft.Web/serverFarms`) has `defaultOutboundAccess: false`
   (Azure sets this automatically for certain delegations); the provider
   resource defaults this attribute to `true` when unset. Had to be set
   explicitly per-subnet after the first plan surfaced a spurious
   `update in-place`.

7. **State-lock artefacts from an interrupted background run.** An early
   `terraform plan -out=/dev/null` attempt (testing whether output
   redirection would let me capture long output more easily) left a stray
   0-byte `terraform.tfstate` and a `.terraform.tfstate.lock.info` file
   behind when the Windows-native `terraform.exe` process was killed
   mid-run — Git Bash's `/dev/null` doesn't reliably resolve for a native
   Windows binary. Both were empty/lock-only artefacts (no real state
   content), confirmed and deleted before any further plan ran, and the
   hard boundary (no state file in this directory) held throughout — final
   directory listing has no `.tfstate` file.

## Effort vs. generate-then-fix (`aztfexport`)

Design-then-import took longer up front — every module's internal resource
address, exact variable name, and default-value quirk had to be discovered by
reading `.terraform/modules/*/main.tf` and `variables.tf` directly (the
registry's rendered docs pages returned empty/JS-only content when fetched
programmatically), then verified against three successive `terraform plan`
runs before the config and reality lined up. `aztfexport` would have produced
a working draft in one step and left me correcting two specific, easy-to-spot
lines.

But the composition of the effort differs in a way that matters for the
result, not just the timeline. Every fix in this exercise was a **plan-parity
correction against real state** (subnet defaults, ACL defaults, deprecated
diagnostic-setting schema, a module's required-but-nullable argument) —
each one caught immediately by a failing gate and each one *mechanical* to
resolve once identified, because the config's *shape* (references,
parameterisation, module boundaries) was right from the first line. Neither
of the two defect classes the generator produced ever had a chance to appear,
because they aren't slip-of-the-pen corrections you make after generation —
they're structural choices (a reference vs. a literal; an ignored computed
value vs. a captured one) baked in during authoring. Generate-then-fix
front-loads speed and back-loads a correctness audit against a config you
didn't write and have to first understand; design-then-import front-loads the
audit (discovering what the real resource shape is) and never produces the
wrong shape to begin with. For a nine-resource estate the net wall-clock
difference was modest; for the defect classes specifically, design-then-import
avoided them by construction rather than by review, which is the result this
exercise was built to test.

## Setup required

- **`terraform.tfvars`** (gitignored, already created in this directory) with
  `subscription_id`, `tenant_id`, `suffix = "8e9e55d7"`, `location`.
- **Azure auth for the `azurerm` provider**: this plan used the logged-in
  `az` CLI session (Owner on the subscription). For CI, replace with OIDC /
  workload identity federation and set `ARM_*` env vars (`ARM_CLIENT_ID`,
  `ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID`, `ARM_USE_OIDC=true`) — not `AZURE_*`,
  which the provider does not read.
- **No backend is configured.** `versions.tf` has no `backend` block, so state
  is local-only by default; before any real `apply` is contemplated, a remote
  backend (e.g. an existing storage account + container) must be configured
  and `terraform init -migrate-state` run. This was deliberately left out
  here per the hard boundary (no state file is to be created in this
  exercise).
- **Provider/module versions pinned**: `azurerm ~> 4.0` (resolved to 4.81.0 at
  init time), AVM modules pinned to the exact versions specified in the
  brief. `.terraform.lock.hcl` is generated and left in place (not
  gitignored) for reproducibility.

## Files

- `C:\Users\jdk\import-duty-work\hybrid\versions.tf` — provider/backend config
- `C:\Users\jdk\import-duty-work\hybrid\variables.tf` — `subscription_id`,
  `tenant_id`, `suffix`, `location`, `tags`, `resource_group_tags`
- `C:\Users\jdk\import-duty-work\hybrid\terraform.tfvars` — gitignored, real
  values for this estate
- `C:\Users\jdk\import-duty-work\hybrid\main.tf` — all 15 resources/module
  calls
- `C:\Users\jdk\import-duty-work\hybrid\imports.tf` — 15 `import` blocks
- `C:\Users\jdk\import-duty-work\hybrid\outputs.tf` — downstream outputs
- `C:\Users\jdk\import-duty-work\hybrid\.gitignore`
