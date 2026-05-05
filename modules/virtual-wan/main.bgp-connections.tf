# BGP connection on the Virtual Hub built-in router. Used to peer Network Virtual
# Appliances (NVAs) deployed in spoke virtual networks directly with the vHub.
resource "azurerm_virtual_hub_bgp_connection" "bgp_connection" {
  for_each = var.bgp_connections

  name                          = each.value.name
  peer_asn                      = each.value.peer_asn
  peer_ip                       = each.value.peer_ip
  virtual_hub_id                = module.virtual_hubs.resource_object[each.value.virtual_hub_key].id
  virtual_network_connection_id = each.value.virtual_network_connection_id
}
