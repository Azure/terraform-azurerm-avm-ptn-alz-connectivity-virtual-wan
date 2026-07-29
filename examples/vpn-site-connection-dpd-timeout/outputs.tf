output "actual_dpd_timeout_seconds" {
  description = "The DPD timeout read back from the deployed Azure VPN link connection."
  value       = local.actual_dpd_timeout_seconds

  precondition {
    condition     = local.actual_dpd_timeout_seconds == local.expected_dpd_timeout_seconds
    error_message = "Expected Azure to report dpdTimeoutSeconds=${local.expected_dpd_timeout_seconds}, but received ${coalesce(tostring(local.actual_dpd_timeout_seconds), "null")}. The module did not preserve dpd_timeout_seconds across the VPN site connection pass-through chain."
  }
}

output "vpn_gateway_connection_resource_id" {
  description = "The resource ID of the VPN gateway connection validated by this example."
  value       = data.azapi_resource.vpn_gateway_connection.id
}

output "vwan_outputs" {
  description = "The Virtual WAN module outputs."
  value       = module.test
}
