resource "azapi_resource" "lock" {
  count = var.lock != null ? 1 : 0

  name      = coalesce(module.avm_interfaces.lock_azapi.name, "lock-${var.lock.kind}")
  parent_id = azapi_resource.this.id
  type      = var.resource_types.authorization_locks
  body = {
    properties = merge(
      module.avm_interfaces.lock_azapi.body.properties,
      var.lock.notes == null ? {} : { notes = var.lock.notes }
    )
  }
  ignore_body_changes       = length(var.ignore_body_changes.authorization_locks) > 0 ? var.ignore_body_changes.authorization_locks : null
  response_export_values    = []
  retry                     = var.retry
  schema_validation_enabled = true

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      create = timeouts.value.create
      read   = timeouts.value.read
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }

  depends_on = [azapi_resource.diagnostic_settings, azapi_resource.role_assignments]
}

resource "azapi_resource" "role_assignments" {
  for_each = var.role_assignments

  name                = module.avm_interfaces.role_assignments_azapi[each.key].name
  parent_id           = azapi_resource.this.id
  type                = var.resource_types.authorization_role_assignments
  body                = module.avm_interfaces.role_assignments_azapi[each.key].body
  ignore_body_changes = length(var.ignore_body_changes.authorization_role_assignments) > 0 ? var.ignore_body_changes.authorization_role_assignments : null
  replace_triggers_refs = [
    "properties.principalId",
    "properties.roleDefinitionId",
    "properties.delegatedManagedIdentityResourceId",
  ]
  response_export_values    = []
  retry                     = var.retry
  schema_validation_enabled = true

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      create = timeouts.value.create
      read   = timeouts.value.read
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }
}
