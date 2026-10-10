variable "revision" {
  type    = string
  default = "baseline"
}

variable "enable_telemetry" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "virtual_hubs" {
  type = any
  default = {
    hub = {
      location          = "eastus"
      enabled_resources = { private_dns_resolver = true }
      private_dns_resolver = {
        name                             = null
        resource_group_name              = null
        default_inbound_endpoint_enabled = true
        tags                             = null
        inbound_endpoints = {
          custom   = { name = "custom-in", subnet_name = "snet-custom-in", private_ip_allocation_method = "Dynamic", private_ip_address = null, tags = {}, merge_with_module_tags = false }
          existing = { name = "existing-in", subnet_name = "snet-existing", private_ip_allocation_method = "Dynamic", private_ip_address = null, tags = {}, merge_with_module_tags = false }
        }
        outbound_endpoints = {
          custom = { name = "custom-out", subnet_name = "snet-custom-out", tags = {}, merge_with_module_tags = false }
        }
      }
    }
  }
}
