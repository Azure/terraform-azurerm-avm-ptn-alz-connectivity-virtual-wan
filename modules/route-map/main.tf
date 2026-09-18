
resource "azapi_resource" "route_map" {
  name      = var.name
  parent_id = var.virtual_hub_id
  type      = var.resource_types.virtual_hubs_route_maps
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
  ignore_body_changes = length(var.ignore_body_changes.virtual_hubs_route_maps) > 0 ? var.ignore_body_changes.virtual_hubs_route_maps : null
  retry               = var.retry

  timeouts {
    create = var.timeouts.create
    delete = var.timeouts.delete
    read   = var.timeouts.read
    update = var.timeouts.update
  }
}
