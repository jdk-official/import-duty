resource "azurerm_user_assigned_identity" "this" {
  name                = "id-agentpoc-${var.suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_key_vault" "this" {
  name                       = "kv-agentpoc-${var.suffix}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.this.name
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
}

# Contributor at resource-group scope, held by the user-assigned managed identity
# declared above. This grant is deliberately over-broad - see the Stage 1 review
# (HIGH-3 / MEDIUM-8): Contributor includes storageAccounts/listkeys, which lets
# the identity reach all blob data as the account rather than as itself.
#
# principal_id is a resource reference, not the literal GUID aztfexport emitted.
# The literal pins the assignment to the identity in the ORIGINAL resource group,
# so a fresh apply elsewhere would create a new identity and then grant
# Contributor to the old one.
resource "azurerm_role_assignment" "contributor" {
  scope              = azurerm_resource_group.this.id
  role_definition_id = local.contributor_role_definition_id
  principal_id       = azurerm_user_assigned_identity.this.principal_id
}
