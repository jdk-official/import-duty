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

# This A record is created by the private endpoint's DNS zone group, not by us.
# Azure owns it and stamps a `creator` tag containing the private endpoint's
# resource GUID, and the IP is allocated from snet-pe at deploy time.
#
# aztfexport captured both as if they were user configuration, which made the
# config non-idempotent across environments: a fresh deployment gets a different
# PE GUID and potentially a different address, so every plan showed Terraform
# trying to overwrite Azure's values with the source estate's. Proved by Act 4 -
# the applied copy came back `1 to change` immediately after a successful apply.
#
# Both are Azure-managed, so both are ignored.
resource "azurerm_private_dns_a_record" "blob" {
  name                = "stagentpoc${var.suffix}"
  zone_name           = azurerm_private_dns_zone.blob.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 10
  records             = ["10.42.2.4"]
  tags = {
    creator = "created by private endpoint pe-blob-agentpoc with resource guid f269f680-d047-493c-be5a-82eb5b119ca8"
  }

  lifecycle {
    ignore_changes = [tags, records]
  }
}

resource "azurerm_private_endpoint" "blob" {
  name                = "pe-blob-agentpoc"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.pe.id

  private_service_connection {
    name                           = "conn-blob"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "zg-blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}
