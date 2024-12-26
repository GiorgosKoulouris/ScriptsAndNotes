#!/bin/bash

scriptDir="$(realpath $(dirname $0))"
cd $scriptDir

varFile="$scriptDir/variables.txt"
DB_NAME="$(cat $varFile | grep -E "^DB_NAME" | awk -F'=' '{print $2}')"
BACKUP_DIR="$(cat $varFile | grep -E "^BACKUP_DIR" | awk -F'=' '{print $2}')"
SCRIPT_LOG_DIR="$(cat $varFile | grep -E "^SCRIPT_LOG_DIR" | awk -F'=' '{print $2}')"
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}-bak-$(date +'%Y%m%d_%H%M%S_%z').sql"
PYTHON_ENV="$(cat $varFile | grep -E "^PYTHON_ENV" | awk -F'=' '{print $2}')"

dateToday="$(date +'%Y%m%d')"
logFile="$SCRIPT_LOG_DIR/${dateToday}_dbBackups.log"

print_line() {
    timenow="$(date +'%Y-%m-%d %H:%M:%S %z')"
    echo "$timenow - $1"
    echo "$timenow - $1" >> "$logFile"
}

# Ensure the script log directory exists
mkdir -p "$SCRIPT_LOG_DIR"

# Ensure the backup directory exists
mkdir -p "$BACKUP_DIR"

# Perform the backup using mysqldump
print_line "Creating backup..."
mysqldump \
    --databases "$DB_NAME" \
    --add-drop-database \
    --add-drop-table \
    --create-options \
    --add-locks \
    --lock-tables \
    --flush-logs \
    --master-data > "$BACKUP_FILE"

# Compress the backup file with gzip
print_line "Compressing the backup..."
gzip "$BACKUP_FILE"

# Unlock the database after the backup
print_line "Unlocking database..."
mysql -e "UNLOCK TABLES;"

# Provide feedback
print_line "Backup completed and saved to $BACKUP_FILE.gz"

if [[ "$PYTHON_ENV" != 'NONE' && "$PYTHON_ENV" != 'none' ]]; then
    [ ! -d "$PYTHON_ENV" ] && {
        print_line "ERROR: PYTHON_ENV directory set at file $varFile does not exist ($PYTHON_ENV). Exiting..."
        exit 1
    }
    [ ! -f "$PYTHON_ENV/bin/activate" ] && {
        print_line "ERROR: PYTHON_ENV directory set at file $varFile is not a Python environment ($PYTHON_ENV). Exiting..."
        exit 1
    }
    source "$PYTHON_ENV/bin/activate"
fi

python3 uploadBackupsToS3.py "$BACKUP_FILE.gz"

python3 uploadLogsToS3.py

