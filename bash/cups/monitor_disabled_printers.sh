#!/bin/bash

# Define logging: true|false
WRITE_LOGS_TO_FILE=true
# Define log file location
LOG_FILE_DIR="/var/log/printer_status"
# Date for log file
current_date=$(date +"%Y-%m-%d")
# Define log file name
LOG_FILE="$LOG_FILE_DIR/printers_status_$current_date.log"
# Define log rotation variables
COMPRESS_OLDER_THAN=1
DELETE_OLDER_THAN=7

# Define printers that will not alert when disabled
# Add a new printer on a new line within quotes. Lines can be commented out.
DISABLED_PRINTERS=(
    "tst01" # TicketNumber / Note
    "tst02" # TicketNumber / Note
)

perform_prechecks() {
    if [ "$WRITE_LOGS_TO_FILE" == 'true' ]; then
        # Check that the folder exists
        [ ! -d "$LOG_FILE_DIR" ] && mkdir "$LOG_FILE_DIR"
        # Check that the file exists
        [ ! -f "$LOG_FILE" ] && touch "$LOG_FILE"
        # Fix permissions
        chmod 755 "$LOG_FILE_DIR"
        chmod 644 "$LOG_FILE"
    fi
}

perform_log_rotation() {
    if [ "$WRITE_LOGS_TO_FILE" == 'true' ]; then
        find "$LOG_FILE_DIR" -type f -name "printers_status_*.log" -mtime "+$COMPRESS_OLDER_THAN" -exec tar -czf {}.tar.gz {} \; -exec rm -f {} \;
        find "$LOG_FILE_DIR" -type f -name "printers_status_*.log.tar.gz" -mtime "+$DELETE_OLDER_THAN" -exec rm -f {} \;
    fi
}

script_log() {
    current_time=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$current_time] - $1: $2"
    if [ "$WRITE_LOGS_TO_FILE" == 'true' ]; then
        echo "[$current_time] - $1: $2" >>"$LOG_FILE"
    fi
}

check_printers() {
    # Initialize alerting variable
    is_alerting=0

    lpstat_out="$(lpstat -p)"
    disabled_count=$(echo "$lpstat_out" | grep -iE "^printer.* disabled" | wc -l)
    if [ $disabled_count -eq 0 ]; then
        script_log INFO "No printers found disabled"
    else
        disabled_printers="$(echo "$lpstat_out" | grep -iE "^printer.* disabled" | awk -F' ' '{print $2}')"
        for printer in $(echo "$disabled_printers"); do
            if [[ ! " ${DISABLED_PRINTERS[@]} " =~ " $printer " ]]; then
                script_log WARN "Printer $printer is disabled. Try enabling the printer: cupsenable $printer"
                is_alerting=1
            else
                script_log INFO "Printer $printer is disabled but marked as non-alerting"
            fi
        done
        # This message is only printed for LM, no need to write it on the log file (printed only on errors)
        [ $is_alerting -eq 1 ] && [ "$WRITE_LOGS_TO_FILE" == 'true' ] && {
            echo "[$current_time] - WARN: Review the logs of: $LOG_FILE"
        }
    fi
}

script_log INFO "Execution started"
perform_prechecks
check_printers
perform_log_rotation
script_log INFO "Execution finished"
