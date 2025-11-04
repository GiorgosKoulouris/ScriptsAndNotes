#!/bin/bash

read -p "Enter Azure region (e.g., northeurope): " REGION
read -p "Enter desired number of vCPUs: " CPU
read -p "Enter minimum memory in GB: " MEMORY_GB

MEMORY_MB=$(( MEMORY_GB * 1024 ))

echo
echo "Fetching VM sizes in region '$REGION' with $CPU vCPUs and >= $MEMORY_GB GB memory..."
echo

RESULT=$(az vm list-sizes --location "$REGION" --output json | \
jq -r --arg cpu "$CPU" --arg mem "$MEMORY_MB" '
  .[]
  | select(.numberOfCores != null and .memoryInMB != null)
  | select((.numberOfCores | tonumber) == ($cpu | tonumber) and (.memoryInMB | tonumber) >= ($mem | tonumber))
  | [.name, .numberOfCores, (.memoryInMB / 1024), (.osDiskSizeInMB / 1024), .maxDataDiskCount]
  | @tsv
' | sort -k3 -n)

# Print header
printf "%-30s %-8s %-10s %-12s %-10s\n" "Name" "vCPUs" "Memory(GB)" "OSDisk(GB)" "DataDisks"
printf "%0.s-" {1..75}; echo

# Display results
if [ -z "$RESULT" ]; then
    echo "No VM sizes found matching criteria in region $REGION."
else
    # Add "GB" when printing
    echo "$RESULT" | awk '{printf "%-30s %-8s %-10s %-12s %-10s\n", $1, $2, $3 " GB", $4 " GB", $5}'
fi
