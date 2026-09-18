resource "azurerm_user_assigned_identity" "this" {
  name                = "id-agentpoc-8e9e55d7"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_key_vault" "this" {
  name                       = "kv-agentpoc-8e9e55d7"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.this.name
  tenant_id                  = "11111111-1111-1111-1111-111111111111"
  sku_name                   = "standard"
  soft_delete_retention_days = 7
}

# Contributor on the resource group, held by the pipeline service principal
# (33333333-3333-3333-3333-333333333333) that created these resources via az CLI.
resource "azurerm_role_assignment" "contributor" {
  scope              = azurerm_resource_group.this.id
  role_definition_id = local.contributor_role_definition_id
  principal_id       = "22222222-2222-2222-2222-222222222222"
}
