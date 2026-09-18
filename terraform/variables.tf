variable "subscription_id" {
  description = "Target Azure subscription ID (Azure subscription 1)."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "location" {
  description = "Azure region for all resources in rg-agentpoc-8e9e55d7."
  type        = string
  default     = "uksouth"
}

locals {
  # Built-in "Contributor" role definition GUID (b24988ac-6180-42a0-ab88-20f7382dd24c),
  # referenced at the subscription scope it was assigned from.
  contributor_role_definition_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
}
