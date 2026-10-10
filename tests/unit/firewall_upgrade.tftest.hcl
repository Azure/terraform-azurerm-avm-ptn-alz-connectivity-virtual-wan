# The published-0.17.2 (azurerm) baseline of the upstream version of this test cannot run here: azurerm -> azapi state
# moves cross providers and are not simulated by mock providers (the real migration is exercised by the live upgrade
# runs recorded in the validation checkpoints). This version keeps the stable-identity and removal behaviors: a
# baseline apply of the azapi candidate, then no-op / removal / disable runs that must not recreate firewalls.
mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-firewall-graph/providers/Microsoft.Network/azureFirewalls/UNEXPECTED-NEW-FIREWALL"
    }
  }
  mock_data "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-firewall-graph/providers/Microsoft.Network/azureFirewalls/UNEXPECTED-NEW-FIREWALL"
      output = {
        properties = {
          hubIPAddresses = { privateIPAddress = "10.0.0.4", publicIPs = { count = 1, addresses = [{ address = "198.51.100.10" }] } }
        }
      }
    }
  }
  mock_data "azapi_resource_list" {
    defaults = { output = { firewalls = [] } }
  }
  mock_data "azapi_client_config" {
    defaults = { subscription_id = "00000000-0000-0000-0000-000000000001" }
  }
}
override_resource {
  target = module.virtual_wan[0].azapi_resource.virtual_wan[0]
  values = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-firewall-graph/providers/Microsoft.Network/virtualWans/vwan" }
}
override_resource {
  target = module.virtual_wan[0].module.virtual_hubs.azapi_resource.this["east"]
  values = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-firewall-graph/providers/Microsoft.Network/virtualHubs/hub-east" }
}
override_resource {
  target = module.virtual_wan[0].module.virtual_hubs.azapi_resource.this["west"]
  values = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-firewall-graph/providers/Microsoft.Network/virtualHubs/hub-west" }
}
mock_provider "modtm" {}
mock_provider "random" {}

run "candidate_baseline" {
  command   = apply
  state_key = "firewall_upgrade"

  module {
    source = "./tests/unit/fixtures/firewall-graph/candidate"
  }

  override_resource {
    target = module.virtual_wan[0].module.firewalls.azapi_resource.fw["edge-east"]
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-firewall-graph/providers/Microsoft.Network/azureFirewalls/baseline-east"
    }
  }

  override_resource {
    target = module.virtual_wan[0].module.firewalls.azapi_resource.fw["edge-west"]
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-firewall-graph/providers/Microsoft.Network/azureFirewalls/baseline-west"
    }
  }

  assert {
    condition     = length(output.snapshot.firewall_resource_ids) == 2 && length(output.snapshot.diagnostic_settings_resource_ids) == 2
    error_message = "The baseline apply must create both keyed firewalls and both diagnostic settings."
  }

  assert {
    condition     = output.snapshot.firewall_resource_ids["edge-east"] != output.snapshot.firewall_resource_ids["edge-west"]
    error_message = "The baseline must have distinct per-key identities, different from the candidate creation sentinel."
  }
}

run "upgrade_plan" {
  command   = plan
  state_key = "firewall_upgrade"

  module {
    source = "./tests/unit/fixtures/firewall-graph/candidate"
  }

  assert {
    condition     = output.snapshot == run.candidate_baseline.snapshot
    error_message = "The upgrade plan must retain all legacy output values and types, including firewall and diagnostic IDs."
  }
}

run "upgrade_apply" {
  command   = apply
  state_key = "firewall_upgrade"

  module {
    source = "./tests/unit/fixtures/firewall-graph/candidate"
  }

  assert {
    condition     = output.snapshot == run.candidate_baseline.snapshot
    error_message = "Applying the upgrade must preserve both firewall identities, diagnostic identities, IP outputs and hub ownership."
  }
}

run "idempotent_plan" {
  command   = plan
  state_key = "firewall_upgrade"

  module {
    source = "./tests/unit/fixtures/firewall-graph/candidate"
  }

  assert {
    condition     = output.snapshot == run.candidate_baseline.snapshot
    error_message = "The second candidate plan must retain every published output."
  }
}

run "remove_one_firewall" {
  command   = apply
  state_key = "firewall_upgrade"

  module {
    source = "./tests/unit/fixtures/firewall-graph/candidate"
  }

  variables {
    configuration = {
      firewall_keys = ["edge-west"]
    }
  }

  assert {
    condition = (
      keys(output.snapshot.firewall_resource_ids) == ["edge-west"] &&
      output.snapshot.firewall_resource_ids["edge-west"] == run.candidate_baseline.snapshot.firewall_resource_ids["edge-west"] &&
      output.snapshot.diagnostic_settings_resource_ids["edge-west-audit"] == run.candidate_baseline.snapshot.diagnostic_settings_resource_ids["edge-west-audit"]
    )
    error_message = "Removing one firewall must remove only that firewall and its diagnostics, without replacing the other key."
  }
}

run "disable_firewalls" {
  command   = apply
  state_key = "firewall_upgrade"

  module {
    source = "./tests/unit/fixtures/firewall-graph/candidate"
  }

  variables {
    configuration = {
      firewall_keys = []
    }
  }

  assert {
    condition     = length(output.snapshot.firewall_resource_ids) == 0 && length(output.snapshot.diagnostic_settings_resource_ids) == 0
    error_message = "The mode guard must allow ordinary firewall and diagnostic removal."
  }
}

run "zero_deployed_hubs" {
  command   = apply
  state_key = "firewall_upgrade"

  module {
    source = "./tests/unit/fixtures/firewall-graph/candidate"
  }

  variables {
    configuration = {
      hub_keys = []
    }
  }

  assert {
    condition     = output.snapshot == null && length(module.virtual_wan) == 0
    error_message = "Disabling all hubs must remove module.virtual_wan[0], including mode markers."
  }
}
