#!/bin/bash

scriptDir="$(realpath $(dirname $0))"
cd $scriptDir

varFile="$scriptDir/variables.txt"
DB_NAME="$(cat $varFile | grep -E "^DB_NAME" | awk -F'=' '{print $2}')"
BACKUP_DIR="$(cat $varFile | grep -E "^BACKUP_DIR" | awk -F'=' '{print $2}')"
SCRIPT_LOG_DIR="$(cat $varFile | grep -E "^SCRIPT_LOG_DIR" | awk -F'=' '{print $2}')"

dateToday="$(date +'%Y%m%d')"
logFile="$SCRIPT_LOG_DIR/${dateToday}_removeOldBackups.log"

print_line() {
    timenow="$(date +'%Y-%m-%d %H:%M:%S %z')"
    echo "$timenow - $1"
    echo "$timenow - $1" >> "$logFile"
}

# Ensure the script log directory exists
mkdir -p "$SCRIPT_LOG_DIR"

# Ensure the backup directory exists
[ ! -d "$BACKUP_DIR" ] && {
    print_line "ERROR: Directory missing ($BACKUP_DIR). Exiting..."
    exit 1
}

message="$(find "$BACKUP_DIR" -type f -name "${DB_NAME}-bak-*.sql.gz" -exec printf '%s\n' {} +)"
[ "$(echo $message | grep -vE "^$" | wc -l)" -gt 0 ] && {
    find "$BACKUP_DIR" -type f -name "${DB_NAME}-bak-*.sql.gz" -exec rm -f {} +
    echo "$message" | while IFS= read -r line; do
        print_line "Deleting $line"
    done
} || print_line "Nothing to delete"

