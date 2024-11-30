# Get list of Resource Groups in your subscription
resource_groups=$(az group list --query "[].name" -o tsv)

# If no Resource Groups exist, exit the script
if [ -z "$resource_groups" ]; then
    echo "No Resource Groups found in your subscription."
    exit 1
fi

# Show the Resource Groups and let the user select one
echo "Select a Resource Group:"
select selected_resource_group in $resource_groups; do
    if [ -n "$selected_resource_group" ]; then
        break
    else
        echo "Invalid choice, try again."
    fi
done

# Get the list of VNets in the selected Resource Group
vnets="$(az network vnet list --resource-group "$selected_resource_group" --query "[].name" -o tsv)"

# If no VNets exist in the selected resource group, exit the script
if [ -z "$vnets" ]; then
    echo "No VNets found in Resource Group $selected_resource_group."
    exit 1
fi

# Show the VNets in the selected Resource Group and let the user select one
echo "Select a VNet in Resource Group $selected_resource_group:"
select selected_vnet_name in $vnets; do
    if [ -n "$selected_vnet_name" ]; then
        break
    else
        echo "Invalid choice, try again."
    fi
done

# Get the resource group for the selected VNet (just for confirmation)
vnet_resource_group=$(az network vnet show --name "$selected_vnet_name" --resource-group "$selected_resource_group" --query "resourceGroup" -o tsv)

# Verify if the resource group is correct
if [ "$vnet_resource_group" != "$selected_resource_group" ]; then
    echo "Error: The selected VNet $selected_vnet_name is not in Resource Group $selected_resource_group."
    exit 1
fi

# Get the list of subnets for the selected VNet and Resource Group
subnets=$(az network vnet subnet list --vnet-name "$selected_vnet_name" --resource-group "$selected_resource_group" --query "[].name" -o tsv)

# If no subnets exist, exit the script
if [ -z "$subnets" ]; then
    echo "No subnets found for VNet $selected_vnet_name in Resource Group $selected_resource_group."
    exit 1
fi

# Show the subnets and let the user select one
echo "Select a Subnet for VNet $selected_vnet_name in Resource Group $selected_resource_group:"
select selected_subnet in $subnets; do
    if [ -n "$selected_subnet" ]; then
        subnetID=$(az network vnet subnet show \
            --name $selected_subnet \
            --vnet-name "$selected_vnet_name" \
            --resource-group "$selected_resource_group" \
            -o json | jq '. | {Name: .name, CIDR: .addressPrefixes[0], ID: .id}')
        echo "$subnetID"
        break
    else
        echo "Invalid choice, try again."
    fi
done