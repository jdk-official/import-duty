provider "azurerm" {
  features {
  }
  use_cli                         = true
  use_oidc                        = false
  resource_provider_registrations = "none"
  subscription_id                 = var.subscription_id
  environment                     = "public"
  use_msi                         = false
}
