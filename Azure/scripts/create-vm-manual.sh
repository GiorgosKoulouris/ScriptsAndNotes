LOCATION=northeurope
VM_NAME=testuftp00

az sshkey list --query '[].id'
SSH_KEY_ID=''

az group list --query ' [].id '
RESOURCE_GROUP=''

az vm image list-publishers \
    --location $LOCATION \
    --output table \
    | grep -i oracle

az vm image list-offers \
    --location $LOCATION \
    --publisher Oracle \
    --output table

az vm image list --all \
    --location $LOCATION \
    --publisher Oracle \
    --offer Oracle-Linux \
    --architecture x64 \
    --output table

IMAGE=''

az vm image show \
    --location $LOCATION \
    --urn "$IMAGE"

vmNumCores=1
vmMemoryMB=1024

# Use Azure CLI to list available VM sizes and filter based on CPU and memory
az vm list-sizes --location $LOCATION --out json |\
    jq --arg vmNumCoresJQ "$vmNumCores" --arg vmMemoryMBJQ "$vmMemoryMB" \
        '.[] | select(.numberOfCores == ($vmNumCoresJQ | tonumber) and .memoryInMB == ($vmMemoryMBJQ | tonumber)) | {VMSize: .name, MaxDataDisks: .maxDataDiskCount}'

VM_SIZE=''

networkCount=$(az network vnet list --query ' [] | length(@)')
counter=0
while [ $counter -lt $networkCount ]
do
    az network vnet list --query " [$counter] | [name, resourceGroup, location, id] "
    counter=$(( $counter + 1 ))
done

VNET_ID=''
VNET_NANE=''

subnetCount=$(az network vnet show --ids $VNET_ID --query " subnets | [] | length(@) ")
counter=0
while [ $counter -lt $subnetCount ]
do
    az network vnet show --ids $VNET_ID --query " subnets | [$counter] | [name, addressPrefix, resourceGroup, id] "
    counter=$(( $counter + 1 ))
done

SUBNET_ID=''

read -s passwd

# Create the VM with a public IP address
az vm create \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --location $LOCATION \
  --image $IMAGE \
  --size $VM_SIZE \
  --subnet $SUBNET_ID \
  --admin-username azureuser \
  --admin-password "$passwd" \
  --public-ip-sku Standard \
  --no-wait

# Create the VM without a public IP address
az vm create \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --location $LOCATION \
  --image $IMAGE \
  --size $VM_SIZE \
  --subnet $SUBNET_ID \
  --admin-username azureuser \
  --admin-password "$passwd" \
  --no-wait