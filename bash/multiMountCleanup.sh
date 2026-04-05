#!/bin/bash

# ----- Execution Options ---------

# Comment any FS types you don't need to be checked
FS_TYPES=(
    "bind"
    "nfs"
    "cifs"
)

# Logging settings
LOG_TO_FILE="false"
LOG_FILE="/tmp/multiMountCleanup.log"


# ----- Runtime Variables ---------

DRY_RUN="false"
LAZY_UNMOUNT="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        -l|--lazy)
            LAZY_UNMOUNT="true"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [-n|--dry-run] [-l|--lazy]"
            echo "  -n, --dry-run   Show what would be done"
            echo "  -l, --lazy      Allow lazy unmount (umount -l) for duplicate mounts"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [-n|--dry-run] [-l|--lazy]"
            exit 1
            ;;
    esac
done

# ----- Function definitions ---------

# Log function
script_log() {
    local level="$1"
    local msg="$2"
    local ts
    ts=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$ts] [$level] - $msg"
    if [ "$LOG_TO_FILE" = "true" ]; then
        echo "[$ts] [$level] - $msg" >> "$LOG_FILE"
    fi
}

# Dry-run VS normal execution handling
run_cmd() {
    if [ "$DRY_RUN" = "true" ]; then
        script_log DRY "Would run: $*"
        return 0
    fi
    "$@"
}

# Check root
if [[ $EUID -ne 0 ]]; then
   script_log ERR "This script must be run as root."
   exit 1
fi


# --- Collect mounts from fstab
declare -A MOUNTS   # target -> type
for fs in "${FS_TYPES[@]}"; do
    if [ "$fs" = "bind" ]; then
        while read -r target; do
            MOUNTS["$target"]="bind"
        done < <(findmnt -sn -O bind -o TARGET)
    else
        while read -r target; do
            MOUNTS["$target"]="$fs"
        done < <(findmnt -sn -t "$fs" -o TARGET)
    fi
done

if [ "${#MOUNTS[@]}" -eq 0 ]; then
    script_log INFO "No matching mounts found in /etc/fstab. Exiting."
    exit 0
fi

script_log INFO "Mounts defined in fstab:"
for m in "${!MOUNTS[@]}"; do
    script_log INFO "    $m (${MOUNTS[$m]})"
done


# --- Mount missing mounts
for mountpoint in "${!MOUNTS[@]}"; do
    if ! findmnt -rm -o TARGET | grep -Fx "$mountpoint" > /dev/null; then
        script_log WARN "$mountpoint is not mounted. Mounting..."
        run_cmd mount "$mountpoint" || \
            script_log ERR "Failed to mount $mountpoint"
    fi
done

# --- Remove duplicate mount instances
for mountpoint in "${!MOUNTS[@]}"; do
    count=$(findmnt -rm -o TARGET | grep -Fx "$mountpoint" | wc -l)
    script_log INFO "$mountpoint has $count mount instance(s)."

    while [ "$count" -gt 1 ]; do
        script_log WARN "Unmounting extra instance of $mountpoint"

        if ! run_cmd umount "$mountpoint"; then
            if [ "$LAZY_UNMOUNT" = "true" ]; then
                script_log WARN "Normal unmount failed, trying lazy unmount"
                run_cmd umount -l "$mountpoint" || {
                    script_log ERR "Failed to lazy-unmount $mountpoint"
                    break
                }
            else
                script_log ERR "Unmount failed and lazy unmount not enabled. Execute with lazy option (-l|--lazy)"
                break
            fi
        fi

        if [ "$DRY_RUN" = "true" ]; then
            break
        fi

        count=$(findmnt -rm -o TARGET | grep -Fx "$mountpoint" | wc -l)
    done
done

# --- Verification
for mountpoint in "${!MOUNTS[@]}"; do
    if findmnt -rm -o TARGET | grep -Fx "$mountpoint" > /dev/null; then
        script_log INFO "$mountpoint is mounted and healthy."
    else
        script_log ERR "$mountpoint is NOT mounted."
    fi
done

script_log INFO "Completed successfully."
