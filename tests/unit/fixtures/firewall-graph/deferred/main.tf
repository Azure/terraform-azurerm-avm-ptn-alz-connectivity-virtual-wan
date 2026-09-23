module "inputs" {
  source = "../inputs"

  configuration = var.configuration
}

module "virtual_wan" {
  source = "../../../../../modules/virtual-wan"
  count  = module.inputs.enabled ? 1 : 0

  location                           = "uksouth"
  resource_group_name                = "rg-firewall-graph"
  virtual_wan_name                   = "vwan-firewall-graph"
  diagnostic_settings_azure_firewall = module.inputs.diagnostic_settings
  enable_telemetry                   = false
  firewalls                          = module.inputs.firewalls
  virtual_hubs                       = module.inputs.virtual_hubs

  # Deliberately not the Accelerator's ordinary resource-group wiring.
  depends_on = [module.inputs]
}
