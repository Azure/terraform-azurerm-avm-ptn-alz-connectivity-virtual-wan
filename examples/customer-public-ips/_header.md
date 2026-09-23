# Customer-owned secured-hub public IPs

Qualification fixture for the pattern candidate. It creates a resource group, caller-owned Standard/static IPv4 public IPs and an Azure Firewall policy with AzAPI, then invokes the actual pattern with computed public IP IDs. It retains the existing AzureRM 4 implementation for the surrounding legacy topology; no AzureRM 5 upgrade is included.

Supply `location`, a unique `name_prefix`, `resource_group_name`, and a nonempty `public_ip_names` map. Run only in an explicitly owned disposable Azure environment with approved subscription firewall-inventory read permission and deployment permissions. The fixture has not been deployed as part of the local candidate work.

This manual qualification fixture is excluded from automatic E2E discovery because it requires explicit lab inputs and ownership approval. Approve deployment, monitoring and cleanup before running it; no cloud apply is part of the local unit suite.

Keep the resource group and firewall names stable. Test one and multiple IPs, then same-mode additions, removals and replacements, with an unchanged follow-up plan after each apply. Because this *caller* owns the example IP resources, removing a `public_ip_names` entry also requests deletion of that caller resource; use a separate caller-owned IP pool when proving that firewall detachment alone preserves an IP. Do not remove the final firewall IP or attempt mode conversion.

Capture ARM IDs, actual public IP `properties.ipConfiguration.id` association paths, allocated address strings, request/response counts, operation durations and continuous traffic results. Measure traffic interruption separately from control-plane elapsed time. This fixture does not prove the unchanged managed-state upgrade, diagnostic migration/identity, or a zero-downtime guarantee; those remain separate release gates.
