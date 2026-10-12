variable "configuration" {
  type = object({
    hub_keys       = optional(set(string), ["east", "west"])
    firewall_keys  = optional(set(string), ["edge-east", "edge-west"])
    customer_keys  = optional(set(string), [])
    revision       = optional(number, 0)
    unknown_values = optional(bool, false)
  })
  default     = {}
  description = "Adversarial graph inputs with a deliberately broad module dependency."
  nullable    = false
}
