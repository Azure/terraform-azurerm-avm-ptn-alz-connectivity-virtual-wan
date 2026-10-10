locals {
  er_circuit_connections = var.er_circuit_connections != null ? var.er_circuit_connections : {}

  # AzureRM's Create builds `parameters.Properties` as a struct literal and sends four of these
  # fields UNCONDITIONALLY -- `pointer.To(d.Get(...))`, not "only when the consumer set them".
  # Their schema defaults therefore reached ARM on every create, so a migrated connection has to
  # send the same literals or the first apply after the upgrade would reset live values.
  # Verified against express_route_connection_resource.go at
  # 5782a75422c68a0d0804ac16d97dcaf3df5ee2fa (v4.81.0):
  #   express_route_gateway_bypass_enabled  L78-L82    Default false, sent at L223
  #   routing_weight                        L149-L153  Default 0,     sent at L222
  #   internet_security_enabled             L75-L77    Default false, sent at L220 via L209-L212
  #
  # ⚠️ `internet_security_enabled` needs the note. Under the 4.x feature flag
  # (`if !features.FivePointOh()`, L154-L173) BOTH it and the deprecated
  # `enable_internet_security` are REDECLARED as Optional+Computed with no `Default`. That does
  # not change what create sends: `d.Get` on an unset Optional+Computed bool still returns
  # `false`, and L220 sends it either way. It only changes update, which is guarded by
  # `d.HasChanges` (L330-L339). So the create literal is `false` and that is what is reproduced.
  er_connection_defaults = {
    enable_internet_security             = false
    express_route_gateway_bypass_enabled = false
    routing_weight                       = 0
  }

  er_circuit_connection_bodies = {
    for key, value in local.er_circuit_connections : key => {
      properties = merge(
        {
          expressRouteCircuitPeering = { id = value.express_route_circuit_peering_id }
          enableInternetSecurity     = try(value.enable_internet_security, null) != null ? value.enable_internet_security : local.er_connection_defaults.enable_internet_security
          routingWeight              = try(value.routing_weight, null) != null ? value.routing_weight : local.er_connection_defaults.routing_weight

          # 🔴 DELIBERATE BUG-FOR-BUG PARITY, and note this one is a WRITE, not a drop.
          # `variables.tf` accepts `express_route_gateway_bypass_enabled` (Fast Path) and always
          # has, but the AzureRM resource block never referenced it -- so AzureRM read the
          # schema default and sent `expressRouteGatewayBypass: false` on every create,
          # regardless of what the consumer passed. Every connection this module has ever
          # created therefore has Fast Path explicitly OFF in ARM. Wiring the variable up here
          # would turn a documented-but-inert input into a live one and could enable Fast Path
          # on existing connections at the first post-migration apply. The literal is
          # reproduced; honouring the input is a separate, deliberate change.
          expressRouteGatewayBypass = local.er_connection_defaults.express_route_gateway_bypass_enabled

          # `expandExpressRouteConnectionRouting` (L376-L379) returns an EMPTY STRUCT, never
          # nil, when `routing` is absent -- so `routingConfiguration: {}` was part of every
          # request AzureRM sent, and it stays here.
          #
          # 🔴 This is built from NULLS rather than from `merge()` of conditional objects, and
          # that is not a style choice. `cond ? {} : merge(A, B, C, D)` is an HCL type error
          # the moment the merge yields more than one attribute and those attributes have
          # different types: "Inconsistent conditional result types". It only fires when a
          # consumer sets enough of the optional inputs at once, so it survived
          # `terraform validate` and both migration gates and was caught by
          # `tests/null_optionals.tftest.hcl` run "all_optionals_set". Every
          # branch below is therefore `<object> : null`, which unifies against anything.
          #
          # The nulls are pruned by `ignore_null_property`, which removes null VALUES but
          # leaves an emptied object as `{}` -- so `routing == null` still sends the empty
          # struct AzureRM sent, and a `propagated_route_table` with two empty lists still
          # sends `propagatedRouteTables: {}`.
          routingConfiguration = {
            # Required on this module's `routing` object, so it is present whenever
            # `routing` is, and the guard is only doing the `routing == null` case.
            associatedRouteTable = try(value.routing.associated_route_table_id, null) != null ? { id = value.routing.associated_route_table_id } : null

            # ✅ Unlike `site-to-site-gateway-connection`, this module DOES wire the route
            # maps, so there is no route-map drop to preserve here. Each is guarded on
            # `!= ""` by the expander (L386, L391, L396).
            inboundRouteMap  = try(value.routing.inbound_route_map_id, null) != null && try(value.routing.inbound_route_map_id, "") != "" ? { id = value.routing.inbound_route_map_id } : null
            outboundRouteMap = try(value.routing.outbound_route_map_id, null) != null && try(value.routing.outbound_route_map_id, "") != "" ? { id = value.routing.outbound_route_map_id } : null

            # Guarded on `len(propagatedRouteTable) != 0` (L403), and inside it `labels` and
            # `ids` are each guarded on `len(...) != 0` (L419, L423) -- so an empty list is
            # ABSENT, not sent as `[]`. This differs from the s2s connection module, where
            # `ids` was built unconditionally; the two expanders are genuinely not the same.
            propagatedRouteTables = try(value.routing.propagated_route_table, null) == null ? null : {
              labels = length(try(value.routing.propagated_route_table.labels, null) != null ? value.routing.propagated_route_table.labels : []) > 0 ? value.routing.propagated_route_table.labels : null
              ids = length(try(value.routing.propagated_route_table.route_table_ids, null) != null ? value.routing.propagated_route_table.route_table_ids : []) > 0 ? [
                for route_table_id in value.routing.propagated_route_table.route_table_ids : { id = route_table_id }
              ] : null
            }
          }
        },
        # Guarded by `if v, ok := d.GetOk("authorization_key")` (L227-L229), so an unset or
        # empty key is absent from the request rather than sent as an explicit null.
        try(value.authorization_key, null) != null && try(value.authorization_key, "") != "" ? {
          authorizationKey = value.authorization_key
        } : {},
      )
    }
  }
}

locals {
  # Per-resource timeout defaults. `var.timeouts` keeps its published shape -- same name, same
  # four attributes, same types -- but its attributes no longer carry a blanket `30m`/`5m`
  # default. An attribute the consumer leaves unset now falls back to the default of the
  # AzureRM resource this module replaced. A consumer who sets `var.timeouts` today is
  # unaffected.
  #
  # Cited against terraform-provider-azurerm@5782a75422c68a0d0804ac16d97dcaf3df5ee2fa (v4.81.0).
  #
  # azapi_resource.this -> azurerm_express_route_connection
  #   express_route_connection_resource.go L34-L39: Create 30m, Read 5m, Update 30m, Delete 30m
  timeouts = {
    create = try(var.timeouts.create, null) != null ? var.timeouts.create : "30m"
    read   = try(var.timeouts.read, null) != null ? var.timeouts.read : "5m"
    update = try(var.timeouts.update, null) != null ? var.timeouts.update : "30m"
    delete = try(var.timeouts.delete, null) != null ? var.timeouts.delete : "30m"
  }
}
