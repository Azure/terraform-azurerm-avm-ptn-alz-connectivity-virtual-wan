
resource "azapi_resource" "route_map" {
  name      = var.name
  parent_id = var.virtual_hub_id
  type      = "Microsoft.Network/virtualHubs/routeMaps@2025-05-01"
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
}
