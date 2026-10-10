locals {
  availability_zones = local.has_regions ? {
    for key, value in var.virtual_hubs : key => module.regions[0].regions_by_name[value.location].zones == null ? [] : module.regions[0].regions_by_name[value.location].zones
  } : null
}
