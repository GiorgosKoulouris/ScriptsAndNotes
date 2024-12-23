#!/bin/bash

scriptDir="$(realpath $(dirname $0))"
cd $scriptDir

varFile="$scriptDir/variables.txt"
PYTHON_ENV="$(cat $varFile | grep -E "^PYTHON_ENV" | awk -F'=' '{print $2}')"
SCRIPT_LOG_DIR="$(cat $varFile | grep -E "^SCRIPT_LOG_DIR" | awk -F'=' '{print $2}')"

dateToday="$(date +'%Y%m%d')"
logFile="$SCRIPT_LOG_DIR/${dateToday}_uploadBackups.log"

print_line() {
    timenow="$(date +'%Y-%m-%d %H:%M:%S')"
    echo "$timenow - $1"
    echo "$timenow - $1" >> "$logFile"
}

# Ensure the script log directory exists
mkdir -p "$SCRIPT_LOG_DIR"

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

python3 uploadBackupsToS3.py