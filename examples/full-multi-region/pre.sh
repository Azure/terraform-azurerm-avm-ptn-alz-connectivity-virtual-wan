echo "Downloading and creating the test.auto.tfvars file from https://raw.githubusercontent.com/Azure/alz-terraform-accelerator/refs/heads/main/templates/platform_landing_zone/examples/full-multi-region/virtual-wan.tfvars..."
#curl -o test.auto.tfvars https://raw.githubusercontent.com/Azure/alz-terraform-accelerator/refs/heads/main/templates/platform_landing_zone/examples/full-multi-region/virtual-wan.tfvars
echo "File downloaded successfully."
echo "Adding randomness to the resource group names..."
randomness=$(echo $RANDOM | md5sum | head -c 4)
sed -i "s/rg-/rg-$randomness-/g" test.auto.tfvars
echo "Randomness added to the resource group names."