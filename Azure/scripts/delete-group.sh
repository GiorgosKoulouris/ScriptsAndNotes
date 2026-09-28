#!/bin/sh

az group list --query " [].name "

echo "Which resource group to delete?"
read groupName

az group delete --name $groupName --no-wait