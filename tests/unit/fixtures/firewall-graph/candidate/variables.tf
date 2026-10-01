variable "configuration" {
  type = object({
    hub_keys       = optional(set(string), ["east", "west"])
    firewall_keys  = optional(set(string), ["edge-east", "edge-west"])
    customer_keys  = optional(set(string), [])
    revision       = optional(number, 0)
    unknown_values = optional(bool, false)
  })
  default     = {}
  description = "Offline graph scenario inputs shared with the published fixture."
  nullable    = false
}
