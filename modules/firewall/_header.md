# Basic example

This submodule deploys an Azure Firewall in the Virtual Hub to make it secured vHUB.

The existing keyed `azurerm_firewall.fw` and diagnostic-setting resources remain the managed-IP implementation. A nonempty `firewalls[key].ip_configurations` map selects a separate, single-firewall AzAPI child. Each entry requires an explicit `name` and `public_ip_address_id`; stable keys must be known at plan time, while IDs may be computed.

Null `vhub_public_ip_count` remains one managed IP for an empty map, or customer-only mode for a nonempty map. Explicit zero is accepted only with customer IPs. Counts retain their string input type and are converted internally to numbers.

Customer opt-in requires subscription-scoped firewall read permission for AzAPI inventory. The helper reads the AzureRM provider's local client configuration solely to identify the subscription used by its existing resources; this does not perform a new Azure control-plane operation. Managed-only callers instantiate neither this metadata read nor the inventory data source.

The state-only `terraform_data.public_ip_mode` record deliberately keeps its original input. Its postcondition raises an error for a requested mode change even when the marker otherwise has no planned changes. No Azure resource/IP drift is ignored. Keep this resource address stable in future refactors. Removing a firewall also removes the marker normally; no manual state migration is required.

Old resource, virtual-hub, null/empty and diagnostic composite-ID output contracts remain available. Customer maintenance is not guaranteed to be outage-free. The root documentation describes prerequisites and maintenance guidance.
