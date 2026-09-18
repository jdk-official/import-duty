# Stays raw: the AVM module (Azure/avm-res-network-virtualnetwork) implements the
# vnet as an azapi_resource, not azurerm_virtual_network. There is no compatible
# `moved` path between those two resource types/providers, so adopting the module
# would force a destroy/recreate of the vnet (and cascade to the delegated subnet,
# the private endpoint's subnet, and everything attached to them). Poor fit for a
# plan-equivalence refactor - see avm-refactor-report.md.
resource "azurerm_virtual_network" "this" {
  name                = "vnet-agentpoc"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = ["10.42.0.0/16"]
}

resource "azurerm_subnet" "app" {
  name                            = "snet-app"
  resource_group_name             = azurerm_resource_group.this.name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = ["10.42.1.0/24"]
  default_outbound_access_enabled = false

  delegation {
    name = "0"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "pe" {
  name                 = "snet-pe"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.42.2.0/24"]
}

# Stays raw: the AVM module (Azure/avm-res-network-privatednszone) implements the
# zone as an azapi_resource, same replacement-risk reasoning as the vnet above.
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "link-vnet-agentpoc"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.this.id
}

resource "azurerm_private_dns_a_record" "blob" {
  name                = "stagentpoc${var.suffix}"
  zone_name           = azurerm_private_dns_zone.blob.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 10
  records             = ["10.42.2.4"]
  tags = {
    creator = "created by private endpoint pe-blob-agentpoc with resource guid f269f680-d047-493c-be5a-82eb5b119ca8"
  }
}

module "private_endpoint_blob" {
  source  = "Azure/avm-res-network-privateendpoint/azurerm"
  version = "0.2.0"

  name                = "pe-blob-agentpoc"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_resource_id  = azurerm_subnet.pe.id

  enable_telemetry = false

  # Preserve the original's auto-generated NIC name rather than pinning one.
  network_interface_name = null

  private_connection_resource_id  = azurerm_storage_account.this.id
  subresource_names               = ["blob"]
  private_service_connection_name = "conn-blob"

  private_dns_zone_group_name   = "zg-blob"
  private_dns_zone_resource_ids = [azurerm_private_dns_zone.blob.id]
}

moved {
  from = azurerm_private_endpoint.blob
  to   = module.private_endpoint_blob.azurerm_private_endpoint.this
}
