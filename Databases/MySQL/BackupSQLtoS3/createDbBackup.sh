#!/bin/bash

scriptDir="$(realpath $(dirname $0))"
cd $scriptDir

varFile="$scriptDir/variables.txt"
DB_NAME="$(cat $varFile | grep -E "^DB_NAME" | awk -F'=' '{print $2}')"
BACKUP_DIR="$(cat $varFile | grep -E "^BACKUP_DIR" | awk -F'=' '{print $2}')"
SCRIPT_LOG_DIR="$(cat $varFile | grep -E "^SCRIPT_LOG_DIR" | awk -F'=' '{print $2}')"
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}-bak-$(date +%Y%m%d_%H%M%S).sql"

dateToday="$(date +'%Y%m%d')"
logFile="$SCRIPT_LOG_DIR/${dateToday}_createBackup.log"

print_line() {
    timenow="$(date +'%Y-%m-%d %H:%M:%S')"
    echo "$timenow - $1"
    echo "$timenow - $1" >> "$logFile"
}

# Ensure the script log directory exists
mkdir -p "$SCRIPT_LOG_DIR"

# Ensure the backup directory exists
mkdir -p "$BACKUP_DIR"

# Lock the database and create the backup
print_line "Locking database..."
mysql -e "FLUSH TABLES WITH READ LOCK;"

# Perform the backup using mysqldump
print_line "Creating backup..."
mysqldump "$DB_NAME" > "$BACKUP_FILE"

# Compress the backup file with gzip
print_line "Compressing the backup..."
gzip "$BACKUP_FILE"

# Unlock the database after the backup
print_line "Unlocking database..."
mysql -e "UNLOCK TABLES;"

# Provide feedback
print_line "Backup completed and saved to $BACKUP_FILE.gz"
