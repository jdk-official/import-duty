module "log_analytics_workspace" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "0.5.1"

  name                = "law-agentpoc-${var.suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  enable_telemetry = false

  log_analytics_workspace_local_authentication_enabled = true

  # Overrides below hold the workspace's original (open) posture steady. The
  # module defaults both of these to "false" (public internet ingestion/query
  # disabled), which is more secure than the imported workspace - see
  # avm-refactor-report.md ("Log Analytics AVM defaults"). The azurerm provider
  # default when these attributes are unset (as in the original config) is
  # "true" for both.
  log_analytics_workspace_internet_ingestion_enabled = "true"
  log_analytics_workspace_internet_query_enabled     = "true"
}

moved {
  from = azurerm_log_analytics_workspace.this
  to   = module.log_analytics_workspace.azurerm_log_analytics_workspace.this
}

# Extension resource — not returned by resource-group export; imported separately
# via `aztfexport resource` and manually added to configuration.
#
# Stays a raw resource: there is no standalone AVM module for diagnostic
# settings (they are exposed as a `diagnostic_settings` input on each AVM
# resource module instead), and its target (the virtual network) also stays
# raw in this pass - see avm-refactor-report.md for why.
resource "azurerm_monitor_diagnostic_setting" "vnet" {
  name                       = "diag-vnet"
  target_resource_id         = azurerm_virtual_network.this.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_metric {
    category = "AllMetrics"
  }
}

# Extension resource — same as above. Target (the storage account) also stays
# raw in this pass.
resource "azurerm_monitor_diagnostic_setting" "storage" {
  name                       = "diag-storage"
  target_resource_id         = azurerm_storage_account.this.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_metric {
    category = "Transaction"
  }
}
