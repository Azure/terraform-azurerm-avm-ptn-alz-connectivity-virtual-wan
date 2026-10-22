mock_provider "azapi" {}

variables {
  er_circuit_connections = {
    test_connection = {
      name                             = "test-er-connection"
      express_route_gateway_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/expressRouteGateways/test-gateway"
      express_route_circuit_peering_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/expressRouteCircuits/test-circuit/peerings/AzurePrivatePeering"
    }
  }
}

run "retry_defaults_when_omitted" {
  command = plan

  assert {
    condition = (
      azapi_resource.er_connection["test_connection"].retry.interval_seconds == 10 &&
      azapi_resource.er_connection["test_connection"].retry.max_interval_seconds == 180 &&
      contains(
        azapi_resource.er_connection["test_connection"].retry.error_message_regex,
        "AnotherOperationInProgress"
      )
    )
    error_message = "Omitted retry settings must use defaults on the resource."
  }
}

run "retry_defaults_when_null" {
  command = plan

  variables {
    retry = null
  }

  assert {
    condition = (
      azapi_resource.er_connection["test_connection"].retry.interval_seconds == 10 &&
      azapi_resource.er_connection["test_connection"].retry.max_interval_seconds == 180 &&
      contains(
        azapi_resource.er_connection["test_connection"].retry.error_message_regex,
        "AnotherOperationInProgress"
      )
    )
    error_message = "Null retry settings must use defaults on the resource."
  }
}

run "retry_partial_override" {
  command = plan

  variables {
    retry = {
      interval_seconds = 20
    }
  }

  assert {
    condition = (
      azapi_resource.er_connection["test_connection"].retry.interval_seconds == 20 &&
      azapi_resource.er_connection["test_connection"].retry.max_interval_seconds == 180 &&
      contains(
        azapi_resource.er_connection["test_connection"].retry.error_message_regex,
        "AnotherOperationInProgress"
      )
    )
    error_message = "Partial retry settings must retain defaults for unspecified resource settings."
  }
}