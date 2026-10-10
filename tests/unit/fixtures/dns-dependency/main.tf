module "virtual_network_side_car" {
  source   = "./sidecar"
  for_each = var.virtual_hubs

  revision = var.revision
}
