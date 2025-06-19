#!/bin/bash

# Prints info about the mapping of OS disks and EBS Volume IDs
#
# Columns:
#   - Device name
#   - EBS Volume ID
#   - Usage (mountpoint, VG etc)
#
# Usage:
#   chmod +x getAwsVolumeMappings.sh
#   ./getAwsVolumeMappings.sh
#
# Usage with TANM as a sensor (comma-delimited):
#   chmod +x getAwsVolumeMappings.sh
#   ./getAwsVolumeMappings.sh --tanium-exec
#

set -euo pipefail

tanium_exec=false

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --tanium-exec)
            tanium_exec=true
            shift 1
            ;;
        *)
            echo "Invalid argument"
            exit 1
            ;;
    esac
done

if [ $tanium_exec == 'false' ]; then
    printf "%-15s %-25s %-50s\n" "DEVICE" "VOLUME_ID" "USAGE"
    printf "%-15s %-25s %-50s\n" "------" "---------" "-----"
fi

# Build device map (not used, but ready if needed)
declare -A DEV_MAP
while read -r DEV MAJMIN; do
    DEV_MAP["$MAJMIN"]="$DEV"
done < <(lsblk -rpno NAME,MAJ:MIN)

# Loop over block devices with SERIAL
lsblk -rpno NAME,SERIAL | while read -r DEV VOLID; do
    [[ -z "$VOLID" ]] && continue

    VOLID="$(echo $VOLID | sed 's/vol/vol-/g')"

    USAGE=""
    REAL_DEV=$(realpath "$DEV")

    # Check if WHOLE device is mounted as "/"
    WHOLE_MNT=$(lsblk -nrpo MOUNTPOINT "$DEV" | grep -v '^$' || true)
    if [[ "$WHOLE_MNT" == "/" ]]; then
        USAGE="Root"
    fi

    # If not, check partitions
    if [[ -z "$USAGE" ]]; then
        PARTS=$(lsblk -nrpo NAME "$DEV")
        while read -r PART; do
            MP=$(lsblk -nrpo MOUNTPOINT "$PART" | grep -v '^$' || true)
            if [[ "$MP" == "/" ]]; then
                USAGE="Root"
                break  # stop processing this device
            fi
        done <<< "$PARTS"
    fi

    # If not Root FS, check if WHOLE device is a PV
    if [[ -z "$USAGE" ]]; then
        while read -r PV VG; do
            PV_REAL=$(realpath "$PV" 2>/dev/null || echo "$PV")
            if [[ "$PV_REAL" == "$REAL_DEV" ]]; then
                USAGE="$VG"
                break
            fi
            PV_MAJMIN=$(lsblk -rpno MAJ:MIN "$PV_REAL" 2>/dev/null || true)
            DEV_MAJMIN=$(lsblk -rpno MAJ:MIN "$REAL_DEV" 2>/dev/null || true)
            if [[ -n "$PV_MAJMIN" && "$PV_MAJMIN" == "$DEV_MAJMIN" ]]; then
                USAGE="$VG"
                break
            fi
        done < <(pvs --noheadings -o pv_name,vg_name 2>/dev/null)
    fi

    # If still no usage, check partitions again (LVM or mountpoints)
    if [[ -z "$USAGE" ]]; then
        PARTS=$(lsblk -nrpo NAME "$DEV")
        while read -r PART; do
            REAL_PART=$(realpath "$PART")
            MP=$(lsblk -nrpo MOUNTPOINT "$PART" | grep -v '^$' || true)
            if [[ -n "$MP" ]]; then
                if [[ -z "$USAGE" ]]; then
                    USAGE="$MP"
                else
                    USAGE="$USAGE|$MP"
                fi
            fi

            while read -r PV VG; do
                PV_REAL=$(realpath "$PV" 2>/dev/null || echo "$PV")
                if [[ "$PV_REAL" == "$REAL_PART" ]]; then
                    USAGE="$VG"
                    break 2
                fi
                PV_MAJMIN=$(lsblk -rpno MAJ:MIN "$PV_REAL" 2>/dev/null || true)
                PART_MAJMIN=$(lsblk -rpno MAJ:MIN "$REAL_PART" 2>/dev/null || true)
                if [[ -n "$PV_MAJMIN" && "$PV_MAJMIN" == "$PART_MAJMIN" ]]; then
                    USAGE="$VG"
                    break 2
                fi
            done < <(pvs --noheadings -o pv_name,vg_name 2>/dev/null)
        done <<< "$PARTS"
    fi

    # If no usage found
    [[ -z "$USAGE" ]] && USAGE="(unused)"

    # Print result
    if [ $tanium_exec == 'false' ]; then
        printf "%-15s %-25s %-50s\n" "$DEV" "$VOLID" "$USAGE"
    else
        echo "$DEV,$VOLID,$USAGE"
    fi
done
