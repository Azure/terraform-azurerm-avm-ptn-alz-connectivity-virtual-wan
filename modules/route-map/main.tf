resource "azapi_resource" "route_map" {
  name      = var.name
  parent_id = var.virtual_hub_id
  type      = var.resource_types.network_virtual_hubs_route_maps
  body = {
    properties = {
      associatedInboundConnections  = var.associated_inbound_connections
      associatedOutboundConnections = var.associated_outbound_connections
      rules = [for rule in var.rules : {
        name              = rule.name
        nextStepIfMatched = rule.next_step_if_matched
        actions = [for action in rule.actions : {
          type = action.type
          parameters = [for param in action.parameters : {
            asPath      = param.as_path
            community   = param.community
            routePrefix = param.route_prefix
          }]
        }]
        matchCriteria = [for criterion in rule.match_criteria : {
          matchCondition = criterion.match_condition
          asPath         = criterion.as_path
          community      = criterion.community
          routePrefix    = criterion.route_prefix
        }]
      }]
    }
  }
  # Write-only argument, so collapse an empty list to null to keep it absent when unused.
  ignore_body_changes = length(var.ignore_body_changes.network_virtual_hubs_route_maps) > 0 ? var.ignore_body_changes.network_virtual_hubs_route_maps : null
  # ✅ TFFR4 (Severity-MUST, Class-Pattern) requires `response_export_values` on every AzAPI
  # resource, "even if empty". `[]` is correct here: `outputs.tf` publishes `.name`, `.id` and
  # the resource object, and the computed-output rule keeps a computed `.output` out of a module output.
  #
  # ⛔ NO `lifecycle { ignore_changes = [response_export_values] }` -- WITHDRAWN, AND IT MUST
  # NOT COME BACK. This site is "armed": `ignore_body_changes` leaves `body` free, so
  # `skip.CanSkipExternalRequest` is false and a PUT does occur. Pinning `response_export_values`
  # here reproduces BUG 3: the pin freezes `plan.Output` to the stale null-derived default
  # projection while the writer still PUTs at adoption, so the applied output disagrees with the
  # planned one -> "Error: Provider produced inconsistent result after apply" on first apply
  # after upgrade. Do not copy this withdrawal onto a Class A (fully silent) writer -- there,
  # pinning costs nothing extra since no PUT happens, and BUG 3 cannot fire either way.
  response_export_values = []
  retry                  = var.retry

  timeouts {
    create = var.timeouts.create
    delete = var.timeouts.delete
    read   = var.timeouts.read
    update = var.timeouts.update
  }
}
