variable "revision" {
  type = string
}

resource "terraform_data" "subnet" {
  for_each = {
    dns_resolver = "snet-dns"
    custom_in    = "snet-custom-in"
    custom_out   = "snet-custom-out"
  }

  input = {
    name     = each.value
    revision = var.revision
  }
}

output "resource_id" {
  value = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test"
}

output "subnets" {
  value = { for key, subnet in terraform_data.subnet : key => { name = subnet.input.name } }
}
