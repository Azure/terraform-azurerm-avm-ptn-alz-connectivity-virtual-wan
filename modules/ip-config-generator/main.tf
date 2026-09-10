variable "public_ips" {
  type = list(object({
    name         = optional(string, "assigned")
    public_ip_id = string
  }))
  description = "A list of public IP addresses."
  default     = []
}

locals {
  ip_configurations = [
    for ip in var.public_ips : {
      name = ip.name
      properties = {
        publicIPAddress = {
          id = ip.public_ip_id
        }
      }
    }
  ]
}

output "ip_configurations" {
  value = local.ip_configurations
}