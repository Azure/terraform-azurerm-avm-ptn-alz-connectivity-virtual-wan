module "inputs" {
  source = "../inputs"

  configuration = var.configuration
}

# This is the published implementation, not a copied firewall facsimile.
module "virtual_wan" {
  source  = "Azure/avm-ptn-alz-connectivity-virtual-wan/azurerm//modules/virtual-wan"
  version = "0.17.2"
  count   = module.inputs.enabled ? 1 : 0

  location                           = "uksouth"
  resource_group_name                = "rg-firewall-graph"
  virtual_wan_name                   = "vwan-firewall-graph"
  diagnostic_settings_azure_firewall = module.inputs.diagnostic_settings
  enable_telemetry                   = false
  firewalls                          = module.inputs.firewalls
  virtual_hubs                       = module.inputs.virtual_hubs
}
