variable "name" {
  type        = string
  description = "The name of the route map."
  nullable    = false
}

variable "virtual_hub_id" {
  type        = string
  description = "The resource ID of the virtual hub to create the route map in."
  nullable    = false
}

variable "associated_inbound_connections" {
  type        = list(string)
  default     = []
  description = "List of connection resource IDs which have this route map associated for inbound traffic."
  nullable    = false
}

variable "associated_outbound_connections" {
  type        = list(string)
  default     = []
  description = "List of connection resource IDs which have this route map associated for outbound traffic."
  nullable    = false
}

variable "rules" {
  type = list(object({
    name                 = string
    next_step_if_matched = optional(string, "Unknown")
    actions = optional(list(object({
      type = string
      parameters = optional(list(object({
        as_path      = optional(list(string), [])
        community    = optional(list(string), [])
        route_prefix = optional(list(string), [])
      })), [])
    })), [])
    match_criteria = optional(list(object({
      match_condition = string
      as_path         = optional(list(string), [])
      community       = optional(list(string), [])
      route_prefix    = optional(list(string), [])
    })), [])
  }))
  default     = []
  description = <<DESCRIPTION
  List of route map rules to apply. Each rule is an object with the following attributes:

  - `name`: The unique name for the rule.
  - `next_step_if_matched`: Next step after rule is evaluated. Supported values are `Continue`, `Terminate`, and `Unknown`. Defaults to `Unknown`.
  - `actions`: Optional list of actions to apply on a match:
    - `type`: Type of action. Supported values are `Add`, `Drop`, `Remove`, `Replace`, and `Unknown`.
    - `parameters`: Optional list of parameters for the action:
      - `as_path`: Optional list of AS paths.
      - `community`: Optional list of BGP communities.
      - `route_prefix`: Optional list of route prefixes.
  - `match_criteria`: Optional list of criteria to match traffic against:
    - `match_condition`: Condition to apply. Supported values are `Contains`, `Equals`, `NotContains`, `NotEquals`, and `Unknown`.
    - `as_path`: Optional list of AS paths to match.
    - `community`: Optional list of BGP communities to match.
    - `route_prefix`: Optional list of route prefixes to match.
  DESCRIPTION
  nullable    = false
}
