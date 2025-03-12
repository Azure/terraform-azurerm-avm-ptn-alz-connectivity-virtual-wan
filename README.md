<!-- BEGIN_TF_DOCS -->
# terraform-azurerm-avm-template

This is a template repo for Terraform Azure Verified Modules.

Things to do:

1. Set up a GitHub repo environment called `test`.
1. Configure environment protection rule to ensure that approval is required before deploying to this environment.
1. Create a user-assigned managed identity in your test subscription.
1. Create a role assignment for the managed identity on your test subscription, use the minimum required role.
1. Configure federated identity credentials on the user assigned managed identity. Use the GitHub environment.
1. Search and update TODOs within the code and remove the TODO comments once complete.

<!-- markdownlint-disable MD033 -->
## Requirements

The following requirements are needed by this module:

- <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) (~> 1.9)

- <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) (~> 4.0)

- <a name="requirement_modtm"></a> [modtm](#requirement\_modtm) (~> 0.3)

- <a name="requirement_random"></a> [random](#requirement\_random) (~> 3.5)

## Resources

The following resources are used by this module:

- [modtm_telemetry.telemetry](https://registry.terraform.io/providers/azure/modtm/latest/docs/resources/telemetry) (resource)
- [random_uuid.telemetry](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/uuid) (resource)
- [azurerm_client_config.telemetry](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) (data source)
- [modtm_module_source.telemetry](https://registry.terraform.io/providers/azure/modtm/latest/docs/data-sources/module_source) (data source)

<!-- markdownlint-disable MD013 -->
## Required Inputs

No required inputs.

## Optional Inputs

The following input variables are optional (have default values):

### <a name="input_enable_telemetry"></a> [enable\_telemetry](#input\_enable\_telemetry)

Description: This variable controls whether or not telemetry is enabled for the module.  
For more information see <https://aka.ms/avm/telemetryinfo>.  
If it is set to false, then no telemetry will be collected.

Type: `bool`

Default: `true`

### <a name="input_tags"></a> [tags](#input\_tags)

Description: (Optional) Tags of the resource.

Type: `map(string)`

Default: `null`

### <a name="input_virtual_hubs"></a> [virtual\_hubs](#input\_virtual\_hubs)

Description: A map of virtual hubs to create.

The following attributes are supported:

  - hub: The virtual hub settings. Detailed information about the virtual hub can be found in the module's README: https://registry.terraform.io/modules/Azure/avm-ptn-virtualwan
  - firewall: (Optional) The firewall settings. Detailed information about the firewall can be found in the Virtual WAN module's README: https://registry.terraform.io/modules/Azure/avm-ptn-virtualwan
  - virtual\_network\_gateways: (Optional) The virtual network gateway settings. Detailed information about the virtual network gateway can be found in the WAN module's README: https://registry.terraform.io/modules/Azure/avm-ptn-virtualwan
  - firewall\_policy: (Optional) The firewall policy settings. Detailed information about the firewall policy can be found in the module's README: https://registry.terraform.io/modules/Azure/avm-ptn-firewall-policy
  - private\_dns\_zones: (Optional) The private DNS zone settings. Detailed information about the private DNS zone can be found in the module's README: https://registry.terraform.io/modules/Azure/avm-ptn-network-private-link-private-dns-zones
  - bastion: (Optional) The bastion host settings. Detailed information about the bastion can be found in the module's README: https://registry.terraform.io/modules/Azure/avm-res-network-bastionhost/
  - side\_car\_virtual\_network: (Optional) The side car virtual network settings. Detailed information about the side car virtual network can be found in the module's README: https://registry.terraform.io/modules/Azure/avm-res-network-virtualnetwork

Type:

```hcl
map(object({
    hub             = any
    firewall        = optional(any)
    firewall_policy = optional(any)
    bastion = optional(object({
      subnet_address_prefix = string
      bastion_host          = any
      bastion_public_ip     = any
    }))
    virtual_network_gateways = optional(object({
      express_route = optional(any)
      vpn           = optional(any)
    }))
    private_dns_zones = optional(object({
      resource_group_name = string
      is_primary          = optional(bool, false)
      private_link_private_dns_zones = optional(map(object({
        zone_name = optional(string, null)
      })))
      auto_registration_zone_enabled = optional(bool, false)
      auto_registration_zone_name    = optional(string, null)
      subnet_address_prefix          = string
      subnet_name                    = optional(string, "dns-resolver")
      private_dns_resolver = object({
        name                = string
        resource_group_name = optional(string)
        ip_address          = optional(string)
      })
    }))
    side_car_virtual_network = optional(any)
  }))
```

Default: `{}`

### <a name="input_virtual_wan_settings"></a> [virtual\_wan\_settings](#input\_virtual\_wan\_settings)

Description: The shared settings for the Virtual WAN. This is where global resources are defined.

The following attributes are supported:

  - ddos\_protection\_plan: (Optional) The DDoS protection plan settings. Detailed information about the DDoS protection plan can be found in the module's README: https://registry.terraform.io/modules/Azure/avm-ptn-ddosprotectionplan  

The Virtual WAN module attributes are also supported. Detailed information about the Virtual WAN module variables can be found in the module's README: https://registry.terraform.io/modules/Azure/avm-ptn-virtualwan

Type: `any`

Default: `{}`

## Outputs

The following outputs are exported:

### <a name="output_dns_server_ip_addresses"></a> [dns\_server\_ip\_addresses](#output\_dns\_server\_ip\_addresses)

Description: The private IP addresses of the DNS servers associated with the virtual WAN.

### <a name="output_firewall_policy_resource_ids"></a> [firewall\_policy\_resource\_ids](#output\_firewall\_policy\_resource\_ids)

Description: The resource IDs of the firewall policies associated with the virtual WAN.

### <a name="output_firewall_private_ip_addresses"></a> [firewall\_private\_ip\_addresses](#output\_firewall\_private\_ip\_addresses)

Description: The private IP addresses of the firewalls associated with the virtual WAN, grouped by hub key.

### <a name="output_firewall_public_ip_addresses"></a> [firewall\_public\_ip\_addresses](#output\_firewall\_public\_ip\_addresses)

Description: The public IP addresses of the firewalls associated with the virtual WAN, grouped by hub key.

### <a name="output_firewall_resource_ids"></a> [firewall\_resource\_ids](#output\_firewall\_resource\_ids)

Description: The resource IDs of the firewalls associated with the virtual WAN, grouped by hub key.

### <a name="output_firewall_resource_names"></a> [firewall\_resource\_names](#output\_firewall\_resource\_names)

Description: The names of the firewalls associated with the virtual WAN, grouped by hub key.

### <a name="output_name"></a> [name](#output\_name)

Description: The name of the virtual WAN.

### <a name="output_resource_id"></a> [resource\_id](#output\_resource\_id)

Description: The resource ID of the virtual WAN.

### <a name="output_virtual_hub_resource_ids"></a> [virtual\_hub\_resource\_ids](#output\_virtual\_hub\_resource\_ids)

Description: The resource IDs of the virtual hubs associated with the virtual WAN.

### <a name="output_virtual_hub_resource_names"></a> [virtual\_hub\_resource\_names](#output\_virtual\_hub\_resource\_names)

Description: The names of the virtual hubs associated with the virtual WAN.

## Modules

The following Modules are called:

### <a name="module_bastion_host"></a> [bastion\_host](#module\_bastion\_host)

Source: Azure/avm-res-network-bastionhost/azurerm

Version: 0.4.0

### <a name="module_bastion_public_ip"></a> [bastion\_public\_ip](#module\_bastion\_public\_ip)

Source: Azure/avm-res-network-publicipaddress/azurerm

Version: 0.2.0

### <a name="module_ddos_protection_plan"></a> [ddos\_protection\_plan](#module\_ddos\_protection\_plan)

Source: Azure/avm-res-network-ddosprotectionplan/azurerm

Version: 0.3.0

### <a name="module_dns_resolver"></a> [dns\_resolver](#module\_dns\_resolver)

Source: Azure/avm-res-network-dnsresolver/azurerm

Version: 0.4.0

### <a name="module_firewall_policy"></a> [firewall\_policy](#module\_firewall\_policy)

Source: Azure/avm-res-network-firewallpolicy/azurerm

Version: 0.3.2

### <a name="module_private_dns_zone_auto_registration"></a> [private\_dns\_zone\_auto\_registration](#module\_private\_dns\_zone\_auto\_registration)

Source: Azure/avm-res-network-privatednszone/azurerm

Version: 0.2.2

### <a name="module_private_dns_zones"></a> [private\_dns\_zones](#module\_private\_dns\_zones)

Source: Azure/avm-ptn-network-private-link-private-dns-zones/azurerm

Version: 0.7.1

### <a name="module_virtual_network_side_car"></a> [virtual\_network\_side\_car](#module\_virtual\_network\_side\_car)

Source: Azure/avm-res-network-virtualnetwork/azurerm

Version: 0.7.1

### <a name="module_virtual_wan"></a> [virtual\_wan](#module\_virtual\_wan)

Source: Azure/avm-ptn-virtualwan/azurerm

Version: 0.9.0

<!-- markdownlint-disable-next-line MD041 -->
## Data Collection

The software may collect information about you and your use of the software and send it to Microsoft. Microsoft may use this information to provide services and improve our products and services. You may turn off the telemetry as described in the repository. There are also some features in the software that may enable you and Microsoft to collect data from users of your applications. If you use these features, you must comply with applicable law, including providing appropriate notices to users of your applications together with a copy of Microsoft’s privacy statement. Our privacy statement is located at <https://go.microsoft.com/fwlink/?LinkID=824704>. You can learn more about data collection and use in the help documentation and our privacy statement. Your use of the software operates as your consent to these practices.
<!-- END_TF_DOCS -->