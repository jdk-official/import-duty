resource "azurerm_resource_group" "this" {
  name     = "rg-agentpoc-8e9e55d7"
  location = var.location
  tags = {
    disposable = "true"
    purpose    = "agent-pipeline-poc"
  }
}
