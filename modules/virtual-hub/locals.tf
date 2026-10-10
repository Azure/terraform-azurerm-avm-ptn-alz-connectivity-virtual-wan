locals {
  # `var.virtual_hubs` is `nullable = false` with a `{}` default, so this guard is unreachable
  # today. Preserved verbatim from the AzureRM `for_each` it replaces.
  virtual_hubs = var.virtual_hubs != null ? var.virtual_hubs : {}
}

locals {
  # ── GENESIS BODY ──────────────────────────────────────────────────────────────────────────────
  # Bug-for-bug reproduction of `resourceVirtualHubCreate`, `virtual_hub_resource.go` L186-214 at
  # azurerm v4.81.0 (`5782a75422c68a0d0804ac16d97dcaf3df5ee2fa`).
  #
  # `VirtualHubProperties` is built as a STRUCT LITERAL (L188-192), so the three fields in it are
  # sent UNCONDITIONALLY; the four below it are each behind `d.GetOk`, which is false for a zero
  # value as well as for an unset one.
  virtual_hub_bodies = {
    for key, value in local.virtual_hubs : key => {
      properties = merge(
        {
          # L189 `AllowBranchToBranchTraffic: pointer.To(d.Get("branch_to_branch_traffic_enabled").(bool))`.
          # Unconditional, and `pointer.To` of a bool is never nil, so `allowBranchToBranchTraffic`
          # was in EVERY create request AzureRM sent. This module exposes no variable for it, so
          # the value AzureRM sent was always the schema default `false` (L73-77). Reproduced as a
          # literal for exactly that reason — it is not a knob, it is AzureRM's behaviour.
          #
          # Note this is sent at CREATE only, in both providers: AzureRM's Update mutates it only
          # behind `if d.HasChange("branch_to_branch_traffic_enabled")` (L276), and with no
          # variable to change, that was never true. The merge writer below therefore omits it,
          # which also means a brownfield hub that has `true` set out of band KEEPS it through
          # adoption.
          allowBranchToBranchTraffic = false

          # L191 `HubRoutingPreference: pointer.To(...)`. Unconditional; the schema default is
          # `ExpressRoute` (L136) and `var.virtual_hubs[*].hub_routing_preference` carries the
          # same default, so this key was always present.
          hubRoutingPreference = value.hub_routing_preference
        },

        # L190 `RouteTable: expandVirtualHubRoute(d.Get("route")...)`. 🔴 DELIBERATELY ABSENT.
        # `expandVirtualHubRoute` returns a NIL pointer for empty input (L414-417), and the field
        # is `*VirtualHubRouteTable json:"routeTable,omitempty"`, so nil means the key was omitted
        # from the request entirely — not sent as an empty object. This module exposes no `route`
        # variable, so the input was always empty and `routeTable` was never in the body. It stays
        # out. It is row 11 of the undeclared table above.

        # L196-198 `if v, ok := d.GetOk("address_prefix"); ok`. `GetOk` on a string is false for
        # "", so an empty prefix omits the key rather than sending "".
        value.address_prefix != null && value.address_prefix != "" ? {
          addressPrefix = value.address_prefix
        } : {},

        # L200-202 `if v, ok := d.GetOk("sku"); ok`.
        value.sku != null && value.sku != "" ? {
          sku = value.sku
        } : {},

        # L204-208 `if v, ok := d.GetOk("virtual_wan_id"); ok` -> `&SubResource{Id: ...}`. ARM takes
        # a SubResource object here, not a bare ID string, and the JSON key is `virtualWan` —
        # lower-case `w` (`model_virtualhubproperties.go` L27). Easy to get wrong.
        value.virtual_wan_id != null && value.virtual_wan_id != "" ? {
          virtualWan = { id = value.virtual_wan_id }
        } : {},

        # L210-214 `if v, ok := d.GetOk("virtual_router_auto_scale_min_capacity"); ok`. 🔴 `GetOk`
        # on an INT is false for 0, so a configured 0 omitted the whole
        # `virtualRouterAutoScaleConfiguration` object rather than sending `minCapacity: 0`.
        # AzureRM's own schema could not produce 0 (`Default: 2`, `IntAtLeast(2)`, L149-154) but
        # this module's `optional(number, 2)` has no such validation, so the guard is reachable
        # here in a way it was not there. Preserved rather than "fixed": a silent change of shape
        # at 0 is exactly the class of difference this migration exists to avoid.
        value.virtual_router_auto_scale_min_capacity != null && value.virtual_router_auto_scale_min_capacity != 0 ? {
          virtualRouterAutoScaleConfiguration = {
            minCapacity = value.virtual_router_auto_scale_min_capacity
          }
        } : {},
      )
    }
  }

  # ── DAY-2 BODY ────────────────────────────────────────────────────────────────────────────────
  # Exactly the subset `resourceVirtualHubUpdate` could mutate THROUGH THIS MODULE, and no more.
  # L276-298 guards five fields with `d.HasChange`:
  #
  #   L276 branch_to_branch_traffic_enabled        -> no module variable, HasChange never fired
  #   L281 route                                   -> no module variable, HasChange never fired
  #   L285 hub_routing_preference                  -> exposed  ✅ below
  #   L289 tags                                    -> exposed  ✅ below
  #   L292 virtual_router_auto_scale_min_capacity  -> exposed  ✅ below
  #
  # `address_prefix` (L69), `sku` (L82), `virtual_wan_id` (L92), `name` (L58) and `location` are
  # ForceNew and so were never part of an update at all.
  virtual_hub_update_bodies = {
    for key, value in local.virtual_hubs : key => {
      # 🔴 `tags` IS DELIBERATELY ABSENT FROM THIS BODY AS OF 0.19.0. It used to sit here as
      # `tags = value.tags != null ? value.tags : {}`, and that is what made REG-1: a merge
      # writer preserves every undeclared key of the live object unconditionally
      # (`utils/json.go` L52-L53), so it can add and change a tag but can NEVER remove one --
      # while L289 `payload.Tags = tags.Expand(...)` ASSIGNED the whole map, so removal worked
      # under AzureRM. Tags now travel on `azapi_resource_action.tags` in `main.tf`, which PUTs
      # at `Microsoft.Resources/tags/default` and REPLACES the whole tag set. There is exactly
      # one tag writer per address after create, and it is not this one. See accepted cost (b).
      properties = merge(
        # L285.
        { hubRoutingPreference = value.hub_routing_preference },
        # L292-297. The `GetOk` guard is INSIDE the `HasChange` guard in the original, so a change
        # to 0 left the previous configuration on the object rather than clearing it. A merge
        # writer reproduces that by construction: omitting the key changes nothing.
        value.virtual_router_auto_scale_min_capacity != null && value.virtual_router_auto_scale_min_capacity != 0 ? {
          virtualRouterAutoScaleConfiguration = {
            minCapacity = value.virtual_router_auto_scale_min_capacity
          }
        } : {},
      )
    }
  }
}
