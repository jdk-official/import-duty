variable "subscription_id" {
  description = "Target Azure subscription ID. No default - supply it per environment."
  type        = string
}

variable "tenant_id" {
  description = "Entra tenant ID the Key Vault belongs to. No default - supply it per environment."
  type        = string
}

variable "suffix" {
  description = "Uniqueness suffix for globally-unique resource names. Override to deploy a second copy of this estate."
  type        = string
  default     = "8e9e55d7"
}

variable "resource_group_name" {
  description = "Resource group to deploy into."
  type        = string
  default     = "rg-agentpoc-8e9e55d7"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "uksouth"
}

locals {
  # Built-in "Contributor" role definition GUID, referenced at subscription scope.
  contributor_role_definition_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
}
