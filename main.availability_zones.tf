module "regions" {
  source  = "Azure/avm-utl-regions/azurerm"
  version = "0.13.2"
  count   = local.has_regions ? 1 : 0

  location               = local.primary_location
  enable_telemetry       = var.enable_telemetry
  has_availability_zones = null
  is_recommended         = null
  use_cached_data        = false
}

locals {
  availability_zones = local.has_regions ? {
    for key, value in var.virtual_hubs : key => module.regions[0].regions_by_name[value.location].zones == null ? [] : module.regions[0].regions_by_name[value.location].zones
  } : null
}
