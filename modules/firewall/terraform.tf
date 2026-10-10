terraform {
  # 1.7, not 1.11. This module reaches for the write-only `ignore_body_changes`
  # argument, but only ever passes `null` unless a consumer opts in, and a null
  # write-only attribute does not require the 1.11 schema. Same reasoning, and
  # the same constraint, as `modules/virtual-network-connection`.
  required_version = "~> 1.9"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
    # Required to resolve this module's mocked child telemetry to Azure/modtm, not hashicorp/modtm.
    # tflint-ignore: terraform_unused_required_providers
    modtm = {
      source  = "Azure/modtm"
      version = "~> 0.3"
    }
  }
}
