resource "azurerm_storage_account" "this" {
  name                     = "stagentpoc${var.suffix}"
  location                 = var.location
  resource_group_name      = azurerm_resource_group.this.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_account_queue_properties" "this" {
  storage_account_id = azurerm_storage_account.this.id

  logging {
    version = "1.0"
    read    = false
    write   = false
    delete  = false
  }

  hour_metrics {
    version = "1.0"
  }

  minute_metrics {
    version = "1.0"
  }
}
