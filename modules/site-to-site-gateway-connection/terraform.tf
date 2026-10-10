terraform {
  # 🔴 1.11, not 1.7. This module sends the per-link pre-shared key through the
  # write-only `sensitive_body` argument, and write-only attributes do not exist
  # before Terraform 1.11 -- a 1.10 CLI fails at PLAN time on the schema, not at
  # apply time on the value, so "only consumers who set a shared_key need 1.11"
  # is not true and must not be relied on.
  required_version = "~> 1.11"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
  }
}
