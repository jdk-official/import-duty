terraform {
  backend "local" {}

  required_providers {
    # Bumped from the exact pin "4.80.0" to satisfy
    # Azure/avm-res-keyvault-vault/azurerm (>= 4.81, < 5.1), the newest lower
    # bound among the AVM modules adopted in this refactor. Still v4 - no major
    # version change. See avm-refactor-report.md ("Provider version bump").
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.81.0, < 5.0.0"
    }
  }
}
