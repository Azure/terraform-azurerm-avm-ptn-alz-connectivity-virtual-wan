module "regions" {
  source  = "Azure/avm-utl-regions/azurerm"
  version = "0.5.2"
  count   = local.has_regions ? 1 : 0

  availability_zones_filter = false
  enable_telemetry          = var.enable_telemetry
  recommended_filter        = false
  use_cached_data           = false
}
