# VPN Site Connection DPD Timeout Example

Deploys a minimal single-region Virtual WAN, VPN gateway, VPN site, and VPN site connection with `dpd_timeout_seconds = 30`. This is the end-to-end regression example for [Azure/Azure-Landing-Zones#4092](https://github.com/Azure/Azure-Landing-Zones/issues/4092).

After deployment, the example reads the VPN gateway connection directly from Azure with AzAPI. The `actual_dpd_timeout_seconds` output has a precondition that fails the deployment unless Azure reports the configured value. This ensures the example detects the attribute being dropped at any layer of the module pass-through chain.

> **Cost and duration:** This example creates a chargeable Virtual WAN S2S VPN gateway. Gateway creation and deletion can each take 20 minutes or longer.
