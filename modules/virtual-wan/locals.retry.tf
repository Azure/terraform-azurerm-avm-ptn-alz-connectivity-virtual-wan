locals {
  # Retry defaults for THIS module's own AzAPI resources.
  #
  # `var.retry` keeps its published shape -- same variable name, same three attributes, same
  # types, same `default = {}` -- but its attributes no longer carry inline defaults. They are
  # restored here instead, verbatim, so every resource in this module plans exactly as it did
  # before. Same move, same reason, as `local.timeouts` in `locals.timeouts.tf`.
  #
  # 🔴 WHY THE DEFAULTS HAD TO MOVE. TFFR7 requires `retry` to cascade to every submodule that
  # directly declares a supported AzAPI resource, and the cascade is a straight
  # `retry = var.retry`. While the defaults sat on the variable, an UNSET `var.retry` was not
  # null -- it was this module's `["ReferencedResourceNotProvisioned"]` -- so the cascade would
  # have overwritten each submodule's own default with it. Two submodules would have measurably
  # regressed: `../expressroute-gateway-connection` and `../site-to-site-gateway-connection`
  # both default to THREE regexes, adding `AnotherOperationInProgress` and
  # `(?s)OperationNotAllowed.*Updating`, because a write to a gateway child 409s while the
  # parent gateway is busy. Narrowing them to one regex would have turned a retried 409 into a
  # failed apply.
  #
  # With the defaults here instead, an unset `var.retry` cascades as an all-null object, and
  # Terraform fills each null from the receiving submodule's own `optional(..., default)`.
  # MEASURED on Terraform 1.16.2: a parent passing an explicitly-null optional attribute gets
  # the child's declared default, not a null. A consumer who DOES set an attribute still
  # overrides it everywhere, parent and submodules alike.
  #
  # The `var.retry == null` branch is preserved rather than collapsed: `var.retry` is not
  # `nullable = false`, and before this change an explicit `retry = null` reached the resources
  # as a null. It still does.
  retry = var.retry == null ? null : {
    error_message_regex  = var.retry.error_message_regex != null ? var.retry.error_message_regex : ["ReferencedResourceNotProvisioned"]
    interval_seconds     = var.retry.interval_seconds != null ? var.retry.interval_seconds : 10
    max_interval_seconds = var.retry.max_interval_seconds != null ? var.retry.max_interval_seconds : 180
  }
}
