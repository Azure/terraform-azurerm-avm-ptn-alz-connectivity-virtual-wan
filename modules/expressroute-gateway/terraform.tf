terraform {
  # No write-only arguments on the ordinary path -- `ignore_body_changes` is the only one in
  # this module and it is collapsed to null when unused -- so the floor stays at the
  # repository's `~> 1.7`. A consumer who actually supplies `ignore_body_changes` needs 1.11,
  # and its description says so. Same reasoning as `modules/expressroute-gateway-connection`.
  required_version = "~> 1.7"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
  }
}
