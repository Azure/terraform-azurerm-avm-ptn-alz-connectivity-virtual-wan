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

Only customer-mode configurations perform subscription firewall inventory. The AzAPI identity needs `Microsoft.Network/azureFirewalls/read` at the firewall subscription, plus read access to the selected hub and public IPs. This inventory distinguishes an existing managed firewall from a fresh customer deployment before Terraform can remove the legacy resource. Matching uses the intended subscription, resource group and firewall name, case-insensitively; a same-name firewall in another resource group is not the target. The firewall name and resource group must therefore be known at plan time: derive them from inputs, not from attributes computed during apply such as a new resource group's `id`. Managed-only configurations perform no new inventory reads and acquire no new inventory permission requirement.

Normal input-value dependencies on newly created resource groups are retained. Discovery does not depend on new public IP or hub IDs. Genuinely deferred inventory or an unresolved target identity cannot be treated as absence: planning stops rather than risking deletion. An explicit, broad `depends_on` on the entire module can defer discovery and is not a substitute for ordinary resource/input dependencies.

### Maintenance

Adding, removing or replacing customer IP entries while keeping at least one entry is a maintenance operation. It is not a zero-downtime guarantee. Keep map keys stable, plan the address/rule changes explicitly, and measure control-plane duration and traffic impact separately. Removing the final customer IP or adding customer IPs to an existing managed firewall is a mode conversion and is blocked. Cross-mode conversion is not supported by this module; disabling/removing the whole firewall remains a destructive operation.

Customer-mode firewall requests use API version `2024-10-01` by default.

## Private DNS Resolver subnet and endpoints

### Which input controls what

| What | Controlled by |
|---|---|
| Whether the `dns_resolver` subnet exists | `enabled_resources.private_dns_resolver` and `enabled_resources.sidecar_virtual_network`. Endpoint settings do not affect it: the subnet is created even when no endpoint uses it. |
| Generated subnet values | `private_dns_resolver.subnet_address_prefix`, `subnet_name` and `subnet_default_outbound_access_enabled` |
| Replacing the subnet (for example to add an NSG) | `sidecar_virtual_network.subnets["dns_resolver"]` (see below) |
| Default inbound endpoint `dns` | Created only when `enabled_resources.private_dns_zones` and `private_dns_resolver.default_inbound_endpoint_enabled` are both `true`. It is always placed in the subnet with the key `dns_resolver`. |
| Custom inbound and outbound endpoints | `private_dns_resolver.inbound_endpoints` and `outbound_endpoints`. Each endpoint's `subnet_name` is the subnet **name** in the sidecar virtual network, not the map key. |
| Azure Firewall DNS proxy servers | The IP address of the inbound endpoint with the key `dns`. Requires the default inbound endpoint (or a custom endpoint with the key `dns`), private DNS zones, an Azure Firewall and a non-Basic firewall SKU. |

### Overriding a generated sidecar subnet

The module generates the `dns_resolver` and `bastion` sidecar subnets first, then merges `sidecar_virtual_network.subnets` last. A user subnet with the same key therefore replaces the generated subnet. This is a supported configuration, and it is how to set subnet properties that the generated subnet does not expose, such as `network_security_group`, `route_table` or `nat_gateway`.

The replacement is **shallow**: the whole generated subnet is replaced, and none of its values are merged into yours. When you override `dns_resolver`:

- Restate `name`, `address_prefixes` and the `Microsoft.Network/dnsResolvers` delegation. DNS resolver endpoints need the delegation.
- `private_dns_resolver.subnet_address_prefix`, `subnet_name` and `subnet_default_outbound_access_enabled` are ignored.
- To move an existing deployment onto the override without replacing the subnet or its endpoints, keep the current subnet name (default `dns-resolver`) and address prefix.
- The default inbound endpoint follows the override automatically. Custom endpoints must use the override's `name` in `subnet_name`.
- An NSG on the resolver subnet must allow DNS traffic (UDP and TCP port 53) from your clients. The rules are up to you.

A custom inbound endpoint with the key `dns` likewise replaces the default inbound endpoint.

```hcl
sidecar_virtual_network = {
  subnets = {
    dns_resolver = {
      name             = "dns-resolver"
      address_prefixes = ["10.0.0.0/28"]
      network_security_group = {
        id = "<NSG resource ID>"
      }
      delegations = [{
        name = "Microsoft.Network.dnsResolvers"
        service_delegation = {
          name = "Microsoft.Network/dnsResolvers"
        }
      }]
    }
  }
}
```