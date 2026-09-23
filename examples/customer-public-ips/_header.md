# Customer-owned secured-hub public IPs

This example creates a resource group, caller-owned Standard/static IPv4 public IPs and an Azure Firewall policy with AzAPI, then deploys the pattern with a secured-hub firewall that uses those public IPs. The public IP IDs are computed during apply. The surrounding topology uses the existing AzureRM 4 implementation.

Supply `location`, a unique `name_prefix`, `resource_group_name`, and a nonempty `public_ip_names` map. The deploying identity needs deployment permissions and `Microsoft.Network/azureFirewalls/read` at the subscription, which customer mode uses for firewall inventory.

This example is excluded from automatic E2E testing because it requires caller-supplied inputs.

Keep the resource group and firewall names stable. Because this example owns the public IP resources, removing a `public_ip_names` entry also deletes that public IP. To detach an IP from the firewall while keeping it, manage the public IPs outside this configuration. Do not remove the final firewall IP or attempt a mode conversion; both are blocked.
