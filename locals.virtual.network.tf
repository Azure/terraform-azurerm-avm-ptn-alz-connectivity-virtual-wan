locals {
  side_car_virtual_networks_enabled = { for key, value in var.virtual_hubs : key => try(value.side_car_virtual_network.enabled, try(value.side_car_virtual_network, null) != null) }
}

locals {
  side_car_virtual_networks = { for key, value in var.virtual_hubs : key => merge({
    name                = "vnet-side-car-${key}"
    location            = value.hub.location
    resource_group_name = value.hub.resource_group
    ddos_protection_plan = local.ddos_protection_plan_enabled ? {
      id     = module.ddos_protection_plan[0].resource.id
      enable = true
    } : try(value.ddos_protection_plan, null)
  }, value.side_car_virtual_network) if local.side_car_virtual_networks_enabled[key] }
}

locals {
  bastion_subnets = { for key, value in var.virtual_hubs : key => {
    bastion = {
      hub_network_key                 = key
      address_prefixes                = [value.bastion.subnet_address_prefix]
      name                            = "AzureBastionSubnet"
      default_outbound_access_enabled = try(value.bastion.subnet_default_outbound_access_enabled, false)
    } } if local.bastions_enabled[key]
  }
  private_dns_resolver_subnets = { for key, value in var.virtual_hubs : key => {
    dns_resolver = {
      hub_network_key  = key
      address_prefixes = [value.private_dns_resolver.subnet_address_prefix]
      name             = value.private_dns_resolver.subnet_name
      delegations = [{
        name = "Microsoft.Network.dnsResolvers"
        service_delegation = {
          name = "Microsoft.Network/dnsResolvers"
        }
      }]
      default_outbound_access_enabled = try(value.private_dns_resolver.subnet_default_outbound_access_enabled, false)
    } } if local.private_dns_resolver_enabled[key]
  }
  subnets = { for key, value in var.virtual_hubs : key => merge(lookup(local.private_dns_resolver_subnets, key, {}), lookup(local.bastion_subnets, key, {}), try(value.side_car_virtual_network.subnets, {})) }
}

locals {
  virtual_network_connections = merge(local.virtual_network_connections_input, local.virtual_network_connections_side_car)
  virtual_network_connections_input = { for virtual_network_connection in flatten([for virtual_hub_key, virtual_hub_value in var.virtual_hubs :
    [for virtual_network_connection_key, virtual_network_connection_value in try(virtual_hub_value.hub.virtual_network_connections, {}) : {
      unique_key                = "${virtual_hub_key}-${virtual_network_connection_key}"
      name                      = virtual_network_connection_value.name
      virtual_hub_key           = virtual_hub_key
      remote_virtual_network_id = virtual_network_connection_value.remote_virtual_network_id
      internet_security_enabled = try(virtual_network_connection_value.internet_security_enabled, null)
      routing                   = try(virtual_network_connection_value.routing, null)
    }]
    ]) : virtual_network_connection.unique_key => {
    name                      = virtual_network_connection.name
    virtual_hub_key           = virtual_network_connection.virtual_hub_key
    remote_virtual_network_id = virtual_network_connection.remote_virtual_network_id
    internet_security_enabled = virtual_network_connection.internet_security_enabled
    routing                   = virtual_network_connection.routing
  } }
  virtual_network_connections_side_car = { for key, value in local.side_car_virtual_networks : "private_dns_vnet_${key}" => {
    name                      = try(var.virtual_hubs[key].side_car_virtual_network.virtual_network_connection_settings.name, "vnet-side-car-${key}")
    virtual_hub_key           = key
    remote_virtual_network_id = module.virtual_network_side_car[key].resource_id
    internet_security_enabled = try(var.virtual_hubs[key].side_car_virtual_network.virtual_network_connection_settings.internet_security_enabled, null)
    routing                   = try(var.virtual_hubs[key].side_car_virtual_network.virtual_network_connection_settings.routing, null)
    } if local.side_car_virtual_networks_enabled[key]
  }
}
