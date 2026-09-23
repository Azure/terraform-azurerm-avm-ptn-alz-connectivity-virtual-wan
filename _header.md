# Azure Landing Zones Platform Landing Zone Connnectivity with Virtual WAN

This module deploys a virtual WAN topology aligned to the Azure Landing Zones (ALZ) and Microsoft Cloud Adoption Framework (CAF) for Azure. The module is designed to be used in conjunction with the [Azure Verified Modules](https://aka.ms/AVM) initiative and is part of the [Microsoft Cloud Adoption Framework Azure Landing Zones](https://aka.ms/alz).

This module is leveraged by the [Azure Landing Zones IaC Accelerator](https://aka.ms/alz), head over there to learn more. It is part of the Azure Verified Modules for Platform Landing Zone (ALZ) set of modules.

## Customer-owned secured-hub public IPs

Configure `virtual_hubs[hub_key].firewall.ip_configurations` to attach caller-owned public IPs. For example, add this firewall configuration to a hub entry:

```hcl
firewall = {
  ip_configurations = {
    primary = {
      name                 = "internet-primary"
      public_ip_address_id = azapi_resource.public_ips["primary"].id
    }
    secondary = {
      name                 = "internet-secondary"
      public_ip_address_id = azapi_resource.public_ips["secondary"].id
    }
  }
}
```

Keys must be stable and known at plan time; public IP resource IDs and the hub ID can be unknown until apply. Names are explicit, not generated. Configuration names must be unique within a firewall, and public IP IDs must be unique across the configured firewalls, ignoring case.

| `ip_configurations` | `vhub_public_ip_count` | Mode |
| --- | --- | --- |
| Empty or omitted | Omitted or null | Managed, one public IP |
| Empty | Positive integral string | Managed, requested count |
| Nonempty | Omitted, null, or `"0"` | Customer-only |
| Nonempty | Positive count | Rejected: modes cannot be mixed |
| Empty | `"0"` | Rejected: not a no-public-IP mode |

`vhub_public_ip_count` retains its published string type. Negative, fractional and nonnumeric counts are rejected. Existing managed firewalls stay on their original AzureRM 4 resource and diagnostic-setting addresses, including the historical moved-block chain. Their count increases/decreases continue to use AzureRM's retained-address behavior; they do not migrate provider or require user state commands. The module automatically records each firewall's original mode in a state-only `terraform_data` resource.

Customer mode requires a Standard or Premium firewall, a Standard hub, and Standard/Regional static IPv4 public IPs in the same subscription and region. An IP must be unassociated or already associated with this exact firewall. The module reads, but does not own or delete, supplied IP resources. Existing firewall policy references, including `firewall_policy.base_policy_id`, and the original firewall output shapes are preserved. Public-IP outputs contain address strings, not resource IDs.

Customer public IPs must carry a zone set matching the firewall's. The module rejects IPs with no zones at plan time, but an IP whose zones merely *differ* from `firewall.zones` is rejected later by Azure at apply with `AzureFirewallZoneConstraintDoesNotMatchPublicIpAddressZoneConstraint`. Public IPs allocated from a public IP prefix inherit the prefix's zones, so set the prefix zones to match the firewall.

### Deploying a managed hub and a customer-IP hub in the same region

This is the natural comparison and migration-staging topology for this feature, and it requires **explicit** `firewall_policy.name` values on each hub. The default naming convention resolves `fwp-hub-${location}-${sequence}` from a constant sequence, so two hubs sharing a region compute the same firewall policy name and the second apply fails partway with an "already exists" error. Set a distinct `firewall_policy.name` per hub:

```hcl
virtual_hubs = {
  managed = {
    # ...
    firewall_policy = { name = "fwp-managed-${var.location}" }
  }
  customer = {
    # ...
    firewall_policy = { name = "fwp-customer-${var.location}" }
  }
}
```

### Discovery and permissions

Only customer-mode configurations perform subscription firewall inventory. The AzAPI identity needs `Microsoft.Network/azureFirewalls/read` at the firewall subscription, plus read access to the selected hub and public IPs. This inventory distinguishes an existing managed firewall from a fresh customer deployment before Terraform can remove the legacy resource. Matching uses the intended subscription, resource group and firewall name, case-insensitively; a same-name firewall in another resource group is not the target. Managed-only configurations perform no new inventory reads and acquire no new inventory permission requirement.

Normal input-value dependencies on newly created resource groups are retained. Discovery does not depend on new public IP or hub IDs. Genuinely deferred inventory or an unresolved target identity cannot be treated as absence: planning stops rather than risking deletion. An explicit, broad `depends_on` on the entire module can defer discovery and is not a substitute for ordinary resource/input dependencies.

### Maintenance

Adding, removing or replacing customer IP entries while keeping at least one entry is a maintenance operation. It is not a zero-downtime guarantee. Keep map keys stable, plan the address/rule changes explicitly, and measure control-plane duration and traffic impact separately. Removing the final customer IP or adding customer IPs to an existing managed firewall is a mode conversion and is blocked. Cross-mode conversion is not supported by this module; disabling/removing the whole firewall remains a destructive operation.

Customer-mode firewall requests use API version `2024-10-01` by default.
