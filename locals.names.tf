locals {
  default_names = {
    for key, value in var.virtual_hubs : key => {
      for key_name, value_name in tomap(var.default_naming_convention) : key_name => templatestring(value_name, {
        location = value.location
        sequence = format(var.default_naming_convention_sequence.padding_format, var.default_naming_convention_sequence.starting_number)
      })
    }
  }
}
