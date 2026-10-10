# Basic example

This submodule deploys an Azure virtual wan virtual hub

> [!IMPORTANT]
> This submodule uses the `azapi` provider with a **two-writer shape**: a create-only
> `azapi_resource` that sends the genesis body once, and an `azapi_update_resource` that performs
> day-2 changes by GET-then-merge. This exists because `Microsoft.Network/virtualHubs` owns child
> collections and back-references that other modules and customers create, and a full PUT that
> omits them is not uniformly safe — `properties.virtualHubRouteTableV2s` is **measured deleted**.
> `modules/virtual-hub/main.tf` documents the full exposure.
>
> Two consequences for consumers:
>
> - Day-2 body changes are **additive** — the merge writer cannot un-set a property.
>   **Tags are the exception**: since 0.19.0 they are written by a separate
>   `Microsoft.Resources/tags` `PUT` that **replaces the whole tag set**, so removing a key from
>   `virtual_hubs[*].tags` removes it in Azure, as it did under `azurerm`. The cost is that a tag
>   set out of band is removed on the next apply and is **not reported as drift**.
> - `address_prefix`, `sku` and `virtual_wan_id` were `ForceNew` on `azurerm_virtual_hub`.
>   Changing one is now a **silent no-op** rather than a hub replacement. Replace the hub
>   explicitly if you need to change them.
