# Customer-owned secured-hub public IPs

This example creates a resource group, caller-owned Standard/static IPv4 public IPs and an Azure Firewall policy with AzAPI, then deploys the pattern with a secured-hub firewall that uses those public IPs. The public IP IDs are computed during apply. The surrounding topology uses the existing AzureRM 4 implementation.

Every input has a default, so the example runs unattended. The deploying identity needs deployment permissions and `Microsoft.Network/azureFirewalls/read` at the subscription, which customer mode uses for firewall inventory.

Customer mode matches existing firewalls by name and resource group while planning, so both must be known at plan time. This example therefore builds `default_parent_id` from the resource group's inputs rather than its `id`, and its e2e `pre.ps1` hook sets a random `name_prefix` for each run instead of using a `random` resource.

Keep the resource group and firewall names stable. Because this example owns the public IP resources, removing a `public_ip_names` entry also deletes that public IP. To detach an IP from the firewall while keeping it, manage the public IPs outside this configuration. Do not remove the final firewall IP or attempt a mode conversion; both are blocked.
