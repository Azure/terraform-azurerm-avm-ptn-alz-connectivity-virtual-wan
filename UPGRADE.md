# Upgrade Notes

## ExpressRoute Connection

### Terraform State Migration

The ExpressRoute connection implementation has changed from `azurerm_express_route_connection` to `azapi_resource` to support retry handling for transient Azure API conflicts.

Migration blocks are provided to map the previous resource addresses to the new resource addresses. Before upgrading an existing deployment, run `terraform plan` using its existing Terraform state. Review the proposed changes and confirm that no unexpected resource replacements or deletions are planned before applying the upgrade.

### Output Compatibility

The ExpressRoute connection module's `resource` output now returns AzAPI resource objects rather than AzureRM ExpressRoute connection objects. Consumers that depend on provider-specific attributes from this output may need to be updated.

Use the `resource_id` output when you only need the ExpressRoute connection resource IDs.

### Terraform Version Requirement

The ExpressRoute connection child module now requires Terraform 1.8 or later.
