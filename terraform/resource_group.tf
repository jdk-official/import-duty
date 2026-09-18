resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags = {
    disposable = "true"
    purpose    = "agent-pipeline-poc"
  }
}
