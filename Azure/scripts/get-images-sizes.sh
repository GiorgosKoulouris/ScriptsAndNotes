#!/bin/sh

az vm image list --query " [].urnAlias "

echo "Choose memory in GB"
read memoryCount
memoryCount=$(( $memoryCount * 1024 ))

echo "Choose core count"
read coreCount

az vm list-sizes --location northeurope --query "[?memoryInMb ==\`$memoryCount\`] | [?numberOfCores ==\`$coreCount\`]"