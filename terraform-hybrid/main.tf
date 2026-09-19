### Resource group ###########################################################
# Kept as a raw azurerm_resource_group: AVM's resource-group module
# (Azure/avm-res-resources-resourcegroup/azurerm) implements the group via
# azapi_resource internally — see hybrid-import-report.md for the verification.

resource "azurerm_resource_group" "this" {
  name     = "rg-agentpoc-${var.suffix}"
  location = var.location
  tags     = var.resource_group_tags
}

### Networking #################################################################
# Kept raw: AVM's virtual-network module also wraps azapi_resource for the
# vnet/subnet core resources. See report for verification detail.

resource "azurerm_virtual_network" "this" {
  name                = "vnet-agentpoc"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = ["10.42.0.0/16"]
  tags                = var.tags
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
  name                              = "snet-pe"
  resource_group_name               = azurerm_resource_group.this.name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = ["10.42.2.0/24"]
  private_endpoint_network_policies = "Disabled"
}

### Storage account #############################################################
# Kept raw: AVM's storage-account module wraps azapi_resource for the core
# account resource. See report for verification detail.

resource "azurerm_storage_account" "this" {
  name                = "stagentpoc${var.suffix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  public_network_access_enabled   = true
  allow_nested_items_to_be_public = true

  tags = var.tags
}

### Private DNS: blob zone #######################################################
# Kept raw: AVM's private-dns-zone module wraps azapi_resource for the zone.
# See report for verification detail.

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "link-vnet-agentpoc"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}

# The A record is created automatically by the private endpoint's DNS zone
# group in a live deployment; it is captured here for import-plan parity only.
# `fqdn` (record name) and `ttl` are user-set. `records` (the allocated IP) and
# the `creator` metadata tag are Azure-managed — written by the private
# endpoint's DNS integration, not by us — so they are excluded from drift
# detection via lifecycle.ignore_changes rather than pinned to the source
# estate's runtime-allocated values.
resource "azurerm_private_dns_a_record" "blob" {
  name                = "stagentpoc${var.suffix}"
  zone_name           = azurerm_private_dns_zone.blob.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 10
  records             = ["10.42.2.4"] # placeholder only; ignored post-import, see lifecycle block

  tags = {
    creator = "placeholder" # Azure-managed; ignored post-import, see lifecycle block
  }

  lifecycle {
    ignore_changes = [records, tags]
  }
}

### Log Analytics workspace ######################################################
# NOT the AVM module (Azure/avm-res-operationalinsights-workspace/azurerm
# 0.5.1), despite that module being on the "found workable" list and using a
# raw azurerm_log_analytics_workspace internally (no azapi involved here).
# Two import-specific defects made it unusable for THIS exercise:
#   1. The module unconditionally creates a `time_sleep.wait_for_ampls_update`
#      helper resource (main.privatelinkscope.tf) with no count/for_each
#      guard, even when Azure Monitor Private Link Scope is never configured.
#      It always plans as "+ create" (import into it is possible in
#      principle, but the id format it expects, "CREATEDURATION,DESTROYDURATION",
#      is a Terraform-local construct with no Azure counterpart to ground it
#      in, so a synthetic import here is not preserving anything real).
#   2. `local_authentication_enabled` is Optional+Computed and co-exists with
#      a deprecated twin (`local_authentication_disabled`) during this
#      provider's migration window. The module hard-sets the new attribute
#      from a non-null variable default; on a fresh import of a resource
#      never previously read by this provider version, refresh leaves the
#      attribute unpopulated, so the config's explicit `true` always plans as
#      a change — a provider Read()/refresh gap, not a real drift.
# A module call cannot receive a `lifecycle` block for its internal resource,
# so neither defect is fixable from the caller. Using the raw resource here
# restores that control. See hybrid-import-report.md.

resource "azurerm_log_analytics_workspace" "this" {
  name                = "law-agentpoc-${var.suffix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  sku                          = "PerGB2018"
  retention_in_days            = 30
  internet_ingestion_enabled   = true
  internet_query_enabled       = true
  local_authentication_enabled = true

  tags = var.tags

  lifecycle {
    # See note above: provider Read()/refresh does not populate this
    # attribute for a resource freshly imported outside Terraform, so the
    # first plan always shows it as a change even though the config value
    # matches the live setting.
    ignore_changes = [local_authentication_enabled]
  }
}

### Key Vault (AVM) ##############################################################

module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.11.0"

  name                = "kv-agentpoc-${var.suffix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tenant_id           = var.tenant_id

  sku_name = "standard"

  legacy_access_policies_enabled = false # rbac_authorization_enabled = !legacy_access_policies_enabled
  public_network_access_enabled  = true
  soft_delete_retention_days     = 7
  purge_protection_enabled       = false

  # The module's network_acls default ({} -> bypass="None", default_action="Deny")
  # does not match the live vault, which has no ARM-level networkAcls object
  # configured at all — the API's own default for that state is
  # bypass=AzureServices/default_action=Allow. Set explicitly to match.
  network_acls = {
    bypass                     = "AzureServices"
    default_action             = "Allow"
    ip_rules                   = []
    virtual_network_subnet_ids = []
  }

  enable_telemetry = false

  tags = var.tags
}

### User-assigned managed identity (AVM) #########################################

module "identity" {
  source  = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version = "0.5.2"

  name                = "id-agentpoc-${var.suffix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  enable_telemetry = false

  tags = var.tags
}

### Role assignment: identity -> Contributor on the resource group ##############
# References the identity module's principal_id output — never a literal GUID.

resource "azurerm_role_assignment" "identity_contributor" {
  scope                = azurerm_resource_group.this.id
  role_definition_name = "Contributor"
  principal_id         = module.identity.principal_id
}

### Private endpoint: blob (AVM) #################################################

module "private_endpoint_blob" {
  source  = "Azure/avm-res-network-privateendpoint/azurerm"
  version = "0.2.0"

  name                = "pe-blob-agentpoc"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_resource_id  = azurerm_subnet.pe.id

  private_connection_resource_id  = azurerm_storage_account.this.id
  private_service_connection_name = "conn-blob"
  subresource_names               = ["blob"]

  # network_interface_name maps to custom_network_interface_name, which was
  # never set on the live private endpoint — Azure auto-generated the NIC
  # name, and azurerm never populates this ForceNew, non-computed attribute
  # from a value it didn't set. The module marks this argument required with
  # no default, but its declared type is nullable, so passing `null`
  # satisfies "required" without pinning the platform-generated name into
  # config. See hybrid-import-report.md.
  network_interface_name = null

  private_dns_zone_group_name   = "zg-blob"
  private_dns_zone_resource_ids = [azurerm_private_dns_zone.blob.id]

  enable_telemetry = false

  tags = var.tags
}

### Diagnostic settings ###########################################################

resource "azurerm_monitor_diagnostic_setting" "vnet" {
  name                       = "diag-vnet"
  target_resource_id         = azurerm_virtual_network.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  # VMProtectionAlerts is a valid category for this resource but is not
  # enabled in the source estate, so no enabled_log block is declared for it —
  # the current provider schema represents only *enabled* categories as
  # blocks; a disabled category is expressed by its absence, not by a flag.
  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "storage" {
  name                       = "diag-storage"
  target_resource_id         = azurerm_storage_account.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  # Capacity is a valid category for this resource but is not enabled in the
  # source estate, so no enabled_metric block is declared for it (see note
  # above).
  enabled_metric {
    category = "Transaction"
  }
}
