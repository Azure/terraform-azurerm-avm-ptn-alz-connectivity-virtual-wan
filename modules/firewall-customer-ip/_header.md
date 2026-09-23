# Customer-IP secured-hub firewall

Deploys one Standard or Premium Azure Firewall in a Standard Virtual Hub using caller-owned Standard/Regional static IPv4 public IPs. The caller owns cardinality; the primary AzAPI resource has no `count` or `for_each`. `parent_id` is the firewall resource group's ARM ID.

`ip_configurations` is a nonempty map of explicit configuration names and public IP resource IDs. Keys determine stable request ordering and must be known at plan time. IDs can be computed. The public IPs must share the firewall's subscription and region, and must be unassociated or already attached to this exact firewall. Public IPs are data sources, never resources owned by this module.

This leaf is customer-only. It rejects an existing managed-IP firewall and does not implement cross-mode conversion. The parent compatibility helper additionally prevents deleting its incumbent resource when a caller attempts to switch implementations. New consumers should prefer the discrete outputs; `legacy_resource` and `legacy_diagnostic_settings_resource_ids` are compatibility adapters for the existing pattern.

Firewall requests use stable API `2024-10-01` by default. The diagnostic-setting API is `2021-05-01-preview` to support log category groups. Schema validation remains enabled. API versions, retry, timeouts and narrow body overrides are exposed; IP ownership, IP configuration and hub association paths cannot be ignored.

Direct leaf consumers can configure canonical `role_assignments` and `lock` interfaces. Both are disabled by default, and the existing pattern does not expose new root-level role or lock capabilities. These extensions are scoped only to this firewall; they do not change or lock the caller-owned public IPs, hub or policy. Roles use the released AVM interface utility's name/definition handling. `skip_service_principal_aad_check` has no effect with AzAPI. The lock is created after diagnostics and roles and removed before them; utility version `0.6.0` does not expose lock notes, so this module adds the canonical `notes` property to its generated body.

Same-mode IP add/remove/replace operations require maintenance planning and measured traffic evidence. Real-Azure create/update/idempotence, association readback and traffic qualification remain release gates for this candidate.
