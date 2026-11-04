variable "location" {
  type        = string
  description = "The Azure region for this module's resources or telemetry deployment."
  nullable    = false
}

variable "firewall_enabled" {
  type    = bool
  default = true
}
