locals {
  # AzureRM builds `BgpConnectionProperties` with `PeerAsn` and `PeerIP` set unconditionally
  # and attaches the sub-resource only behind `if v, ok := d.GetOk(...)`, which is false for
  # both an unset value and an empty string. Verified against
  # virtual_hub_bgp_connection_resource.go at v4.81.0.
  bgp_connection_bodies = {
    for key, value in var.bgp_connections : key => {
      properties = merge(
        {
          peerAsn = value.peer_asn
          peerIp  = value.peer_ip
        },
        try(value.virtual_network_connection_id, null) != null && try(value.virtual_network_connection_id, "") != "" ? {
          hubVirtualNetworkConnection = { id = value.virtual_network_connection_id }
        } : {},
      )
    }
  }
}
