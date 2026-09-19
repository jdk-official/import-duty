variable "subscription_id" {
  description = "Azure subscription id to deploy into. No default — supplied via terraform.tfvars (gitignored) or TF_VAR_subscription_id."
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant id. No default — supplied via terraform.tfvars (gitignored) or TF_VAR_tenant_id."
  type        = string
}

variable "suffix" {
  description = "Deterministic suffix identifying this deployment of the estate, used in every resource name (e.g. 8e9e55d7)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-z]{4,12}$", var.suffix))
    error_message = "suffix must be 4-12 lowercase alphanumeric characters."
  }
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "uksouth"
}

variable "tags" {
  description = "Tags applied to resources below the resource group. The live estate carries no tags at this level — kept empty by default to match, not because tagging is discouraged."
  type        = map(string)
  default     = {}
}

variable "resource_group_tags" {
  description = "Tags applied to the resource group itself."
  type        = map(string)
  default = {
    purpose    = "agent-pipeline-poc"
    disposable = "true"
  }
}
