output "snapshot" {
  description = "Public graph identities after applying the adversarial caller."
  value = module.inputs.enabled ? {
    firewall_resource_ids            = module.virtual_wan[0].firewall_resource_ids
    firewall_resource_names          = module.virtual_wan[0].firewall_resource_names
    firewall_private_ip_address      = module.virtual_wan[0].firewall_private_ip_address
    firewall_public_ip_addresses     = module.virtual_wan[0].firewall_public_ip_addresses
    firewall_ip_addresses            = module.virtual_wan[0].firewall_ip_addresses
    diagnostic_settings_resource_ids = module.virtual_wan[0].diagnostic_settings_azure_firewall_resource_ids
    virtual_hub_resource_ids         = module.virtual_wan[0].virtual_hub_resource_ids
  } : null
}
