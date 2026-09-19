# Import blocks binding the design-first configuration above to the existing
# rg-agentpoc-8e9e55d7 estate. Plan-only: no `terraform import` / `apply` is
# run against these. IDs are taken verbatim from resource-ids.txt, except the
# private DNS A record (grounded read-only via `az network private-dns
# record-set a list`, since resource-ids.txt does not enumerate it).

import {
  to = azurerm_resource_group.this
  id = "/subscriptions/${var.subscription_id}/resourceGroups/rg-agentpoc-${var.suffix}"
}

import {
  to = azurerm_virtual_network.this
  id = "/subscriptions/${var.subscription_id}/resourceGroups/rg-agentpoc-${var.suffix}/providers/Microsoft.Network/virtualNetworks/vnet-agentpoc"
}

import {
  to = azurerm_subnet.app
  id = "/subscriptions/${var.subscription_id}/resourceGroups/rg-agentpoc-${var.suffix}/providers/Microsoft.Network/virtualNetworks/vnet-agentpoc/subnets/snet-app"
}

import {
  to = azurerm_subnet.pe
  id = "/subscriptions/${var.subscription_id}/resourceGroups/rg-agentpoc-${var.suffix}/providers/Microsoft.Network/virtualNetworks/vnet-agentpoc/subnets/snet-pe"
}

import {
  to = azurerm_storage_account.this
  id = "/subscriptions/${var.subscription_id}/resourceGroups/rg-agentpoc-${var.suffix}/providers/Microsoft.Storage/storageAccounts/stagentpoc${var.suffix}"
}

import {
  to = azurerm_private_dns_zone.blob
  id = "/subscriptions/${var.subscription_id}/resourceGroups/rg-agentpoc-${var.suffix}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
}

import {
  to = azurerm_private_dns_zone_virtual_network_link.blob
  id = "/subscriptions/${var.subscription_id}/resourceGroups/rg-agentpoc-${var.suffix}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net/virtualNetworkLinks/link-vnet-agentpoc"
}

import {
  to = azurerm_private_dns_a_record.blob
  id = "/subscriptions/${var.subscription_id}/resourceGroups/rg-agentpoc-${var.suffix}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net/A/stagentpoc${var.suffix}"
}

import {
  to = azurerm_log_analytics_workspace.this
  id = "/subscriptions/${var.subscription_id}/resourceGroups/rg-agentpoc-${var.suffix}/providers/Microsoft.OperationalInsights/workspaces/law-agentpoc-${var.suffix}"
}

import {
  to = module.key_vault.azurerm_key_vault.this
  id = "/subscriptions/${var.subscription_id}/resourceGroups/rg-agentpoc-${var.suffix}/providers/Microsoft.KeyVault/vaults/kv-agentpoc-${var.suffix}"
}

import {
  to = module.identity.azurerm_user_assigned_identity.this
  id = "/subscriptions/${var.subscription_id}/resourceGroups/rg-agentpoc-${var.suffix}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-agentpoc-${var.suffix}"
}

import {
  to = azurerm_role_assignment.identity_contributor
  id = "/subscriptions/${var.subscription_id}/resourceGroups/rg-agentpoc-${var.suffix}/providers/Microsoft.Authorization/roleAssignments/d07294d6-8cf5-4a35-a788-8dfb312ec96f"
}

import {
  to = module.private_endpoint_blob.azurerm_private_endpoint.this
  id = "/subscriptions/${var.subscription_id}/resourceGroups/rg-agentpoc-${var.suffix}/providers/Microsoft.Network/privateEndpoints/pe-blob-agentpoc"
}

import {
  to = azurerm_monitor_diagnostic_setting.vnet
  id = "/subscriptions/${var.subscription_id}/resourceGroups/rg-agentpoc-${var.suffix}/providers/Microsoft.Network/virtualNetworks/vnet-agentpoc|diag-vnet"
}

import {
  to = azurerm_monitor_diagnostic_setting.storage
  id = "/subscriptions/${var.subscription_id}/resourceGroups/rg-agentpoc-${var.suffix}/providers/Microsoft.Storage/storageAccounts/stagentpoc${var.suffix}|diag-storage"
}
