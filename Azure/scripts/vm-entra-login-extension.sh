#!/bin/bash

resourceGroup=''
vmName=''

az vm extension set \
    --publisher Microsoft.Azure.ActiveDirectory \
    --name AADLoginForWindows \
    --resource-group $resourceGroup \
    --vm-name $vmName