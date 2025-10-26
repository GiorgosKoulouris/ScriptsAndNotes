#!/bin/bash

# vi comment_hostfiles.sh
# chmod u+x comment_hostfiles.sh
# ./comment_hostfiles.sh --range-octets 10.0.10 --action DryRun
# ./comment_hostfiles.sh --range-octets 10.0.10 --action Modify

# Default values
hostsFile="/etc/hosts"

# Function to display usage
usage() {
    echo "Usage: $0 --range-octets <CurrentRange> --action <DryRun|Modify>"
    exit 1
}

# Parse options using getopts
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --range-octets)     current_range="$2"          ; shift 2   ;;
        --action)           action="$2"                 ; shift 2   ;;
        --help)             usage                                   ;;
        *)                  echo "Unknown option: $1"   ; usage     ;;
    esac
done

# Validate input
if [[ -z "$current_range" || -z "$action" ]]; then
    echo "Error: Missing required arguments."
    usage
fi

if [[ "$action" != "DryRun" && "$action" != "Modify" ]]; then
    echo "Error: Invalid action specified. Use 'DryRun' or 'Modify'."
    usage
fi

# Generate timestamp for backup filename
timestamp=$(date +"%Y%m%d-%H%M%S")
backupFile="${hostsFile}_${timestamp}.bak"

# Print changes before applying them
echo "The following changes will be made:"
while IFS= read -r line; do
    modifiedLine=$(echo "$line" | sed -E "s/\b^$current_range\./# $current_range./g")

    if [[ "$line" != "$modifiedLine" ]]; then
        echo "From  : $line"
        echo "To    : $modifiedLine"
        echo "--------------------------------------"
    fi
done < "$hostsFile"

# Perform the actual modification if action is "Modify"
if [[ "$action" == "Modify" ]]; then
    # Create a backup
    cp "$hostsFile" "$backupFile"
    echo -e "\nBackup created: $backupFile"

    # Apply changes to the hosts file
    sed -E "s/\b$current_range\./# $current_range./g" "$hostsFile" > "${hostsFile}.tmp"
    mv "${hostsFile}.tmp" "$hostsFile"
    echo -e "\nHosts file updated."
else
    echo -e "\nDryRun mode: No changes were applied."
fi
