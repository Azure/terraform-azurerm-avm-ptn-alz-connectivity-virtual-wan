locals {
  # Retry applied to the root's own children (sidecar VNet, route maps). The Virtual WAN submodule
  # receives `var.retry` unchanged so unset attributes keep its per-resource defaults.
  retry = var.retry == null ? null : {
    error_message_regex = var.retry.error_message_regex != null ? var.retry.error_message_regex : [
      "ReferencedResourceNotProvisioned",
      "UpdateGatewayInProgress",
      "CannotDeleteVirtualHubWhenItIsInUse",
      "InUseVirtualWanCannotBeDeleted",
    ]
    interval_seconds     = var.retry.interval_seconds != null ? var.retry.interval_seconds : 10
    max_interval_seconds = var.retry.max_interval_seconds != null ? var.retry.max_interval_seconds : 180
  }
}
