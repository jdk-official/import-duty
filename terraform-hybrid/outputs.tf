output "resource_group_id" {
  description = "Resource ID of the resource group."
  value       = azurerm_resource_group.this.id
}

output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "key_vault_id" {
  description = "Resource ID of the key vault."
  value       = module.key_vault.resource_id
}

output "key_vault_uri" {
  description = "Data plane URI of the key vault."
  value       = module.key_vault.uri
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace."
  value       = azurerm_log_analytics_workspace.this.id
}

output "identity_id" {
  description = "Resource ID of the user-assigned managed identity."
  value       = module.identity.resource_id
}

output "identity_principal_id" {
  description = "Principal (object) ID of the user-assigned managed identity, for use in downstream role assignments."
  value       = module.identity.principal_id
}

output "identity_client_id" {
  description = "Client ID of the user-assigned managed identity, for use in workload identity federation / app configuration."
  value       = module.identity.client_id
}

output "private_endpoint_blob_id" {
  description = "Resource ID of the blob private endpoint."
  value       = module.private_endpoint_blob.resource_id
}
