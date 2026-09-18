resource "azurerm_log_analytics_workspace" "this" {
  name                         = "law-agentpoc-8e9e55d7"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.this.name
  local_authentication_enabled = true
}

# Extension resource — not returned by resource-group export; imported separately
# via `aztfexport resource` and manually added to configuration.
resource "azurerm_monitor_diagnostic_setting" "vnet" {
  name                       = "diag-vnet"
  target_resource_id         = azurerm_virtual_network.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_metric {
    category = "AllMetrics"
  }
}

# Extension resource — same as above.
resource "azurerm_monitor_diagnostic_setting" "storage" {
  name                       = "diag-storage"
  target_resource_id         = azurerm_storage_account.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_metric {
    category = "Transaction"
  }
}
