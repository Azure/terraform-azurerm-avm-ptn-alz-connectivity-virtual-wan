locals {
  # Timeouts applied to the root's own children (sidecar VNet, route maps, firewall policies). The
  # Virtual WAN submodule receives `var.timeouts` unchanged so unset attributes keep its
  # per-resource defaults (for example 90m for a firewall).
  timeouts = {
    create = var.timeouts.create != null ? var.timeouts.create : "60m"
    read   = var.timeouts.read != null ? var.timeouts.read : "5m"
    update = var.timeouts.update != null ? var.timeouts.update : "60m"
    delete = var.timeouts.delete != null ? var.timeouts.delete : "60m"
  }
}
