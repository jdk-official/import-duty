module "user_assigned_identity" {
  source  = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version = "0.5.2"

  name                = "id-agentpoc-${var.suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  # Telemetry disabled so the plan reflects only the real Azure estate - see
  # avm-refactor-report.md ("AVM telemetry resources") for why.
  enable_telemetry = false

  # Contributor at resource-group scope, held by the user-assigned managed identity
  # declared above. This grant is deliberately over-broad - see the Act 1 review
  # (HIGH-3 / MEDIUM-8): Contributor includes storageAccounts/listkeys, which lets
  # the identity reach all blob data as the account rather than as itself.
  #
  # Folded into the module's own role_assignments interface (which always scopes
  # the assignment to this identity's own principal_id) rather than a standalone
  # azurerm_role_assignment, so the assignment and its principal share a lifecycle.
  # `scope` is a resource reference, not the literal GUID aztfexport emitted, for
  # the same reason noted in the original config: the literal pins the assignment
  # to the resource group in the ORIGINAL export, so a fresh apply elsewhere would
  # create a new resource group and still grant Contributor on the old one.
  role_assignments = {
    contributor = {
      role_definition_id_or_name = local.contributor_role_definition_id
      scope                      = azurerm_resource_group.this.id
    }
  }
}

moved {
  from = azurerm_user_assigned_identity.this
  to   = module.user_assigned_identity.azurerm_user_assigned_identity.this
}

moved {
  from = azurerm_role_assignment.contributor
  to   = module.user_assigned_identity.azurerm_role_assignment.this["contributor"]
}

module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.11.0"

  name                = "kv-agentpoc-${var.suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  enable_telemetry = false

  soft_delete_retention_days = 7

  # The three overrides below hold the vault's original (weak) posture steady.
  # The module's own defaults are all more secure than what was imported - see
  # avm-refactor-report.md ("Key Vault AVM defaults") for the diffs suppressed
  # here and why each one is a deliberate, deferred decision rather than a
  # silent posture change:
  #   - network_acls: module default is {} (bypass=None, default_action=Deny).
  #     Original vault has no network ACLs at all (open, matching the storage
  #     account's public-access posture noted in the estate's known findings).
  public_network_access_enabled = true
  network_acls                  = null
  #   - purge_protection_enabled: module default is true; irreversible once set.
  purge_protection_enabled = false
  #   - legacy_access_policies_enabled: module default is false, which flips
  #     rbac_authorization_enabled to true - a data-plane access-model change,
  #     not just a hardening default. Original vault has RBAC authorization off
  #     (the azurerm provider default when the attribute is unset).
  legacy_access_policies_enabled = true
}

moved {
  from = azurerm_key_vault.this
  to   = module.key_vault.azurerm_key_vault.this
}
