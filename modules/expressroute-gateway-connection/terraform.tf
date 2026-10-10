terraform {
  # No write-only arguments in this module -- `ignore_body_changes` is the only one and it is
  # collapsed to null when unused -- so the floor stays at the repository's `~> 1.7`. A
  # consumer who actually supplies `ignore_body_changes` needs 1.11, and its description
  # says so. This is deliberately NOT the `~> 1.11` that
  # `site-to-site-gateway-connection` now carries: that module sends a pre-shared key
  # through `sensitive_body` on the ordinary path, so its floor binds unconditionally.
  required_version = "~> 1.7"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
  }
}
