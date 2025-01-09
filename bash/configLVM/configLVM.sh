#!/bin/bash

VG_FILE="vg.conf"
LV_FILE="lv.conf"

VG_VAR=''
LV_VAR=''
DRY_RUN='false'
FORCE='false'

declare -A volume_groups
declare -A vg_lvs

usage() {
	echo "Usage:"
	echo
	echo "$0 --modify-files	Will create and let u edit the files. Just paste the content from the corresponding XLS sheet without modifications"
	echo "$0 --prechecks	Perform prechecks only"
	echo "$0 --config-check	Perform all checks and print the commands to validate"
	echo "$0 --config-proceed	Perform prechecks and proceed with the configuration"
	echo "$0 --config-force	Proceed with the configuration applying force (to re-run on existing FS etc)"
	echo "$0 --reset-check	Shows the commands that will be execute to reset actions taken (to re-run if mistakes were made etc)"
	echo "$0 --reset-proceed	Execute the reset based on the commands shown in --reset-check (to re-run if mistakes were made etc)"
	echo "$0 --help		Print this message"
}

print_line() {
	echo
	printf "%s\n" "$(printf '*%.0s' {1..150})"
	echo
	echo "$1"
	echo
}

cmd_handle() {
	if [ "$DRY_RUN" == 'false' ]; then
		eval "$1"
	else
		echo "$1"
	fi
}

init_args() {
	[ "$#" -ne 1 ] && {
		echo "Invalid argument count"
		usage
		exit 1
	}

	case "$1" in
	--modify-files)
		vi "$VG_FILE"
		vi "$LV_FILE"
		exit 0
		;;
	--prechecks)
		DRY_RUN='true'
		option_prechecks
		;;
	--config-check)
		option_config_check
		;;
	--config-proceed)
		option_config_proceed
		;;
	--config-force)
		option_force_proceed
		;;
	--reset-check)
		option_reset_check
		;;
	--reset-proceed)
		option_reset_proceed
		;;
	--help)
		usage
		exit 0
		;;
	*)
		echo "Invalid argument: $arg."
		usage
		exit 1
		;;
	esac

}

option_prechecks() {
	init_vars
	perform_prechecks
}

option_config_proceed() {
	option_prechecks
	create_pvs
	create_vgs
	create_lvs
	create_filesystems
	create_mountpoints
	modify_fstab
	perform_mount_all
}
option_config_check() {
	DRY_RUN='true'
	option_config_proceed
}

option_force_proceed() {
	FORCE='true'
	option_config_proceed
}

option_reset_check() {
	DRY_RUN='true'
	option_reset_proceed
}

option_reset_proceed() {
	option_prechecks
	reset_unmount_fs
	reset_remove_lvs
	reset_remove_vgs
	reset_remove_pvs
	reset_modify_fstab
}

init_vars() {
	print_line "initializing variables..."

	[[ ! -f "$VG_FILE" || ! -f "$LV_FILE" ]] && {
		echo "Conf files missing. Exiting..."
		exit 1
	}

	while IFS=$'\t' read -r DeviceName VG; do
		# Remove leading/trailing spaces
		DeviceName=$(echo "$DeviceName" | xargs)
		VG=$(echo "$VG" | xargs)

		VG_VAR+="$DeviceName"$'\t'"$VG"$'\n'
	done < <(tail -n +2 "$VG_FILE")
	# Remove empty lines
	VG_VAR=$(echo "$VG_VAR" | sed '/^$/d')

	while IFS=$'\t' read -r VgName LvName Size FsType Striped Mountpoint; do
		# Remove leading/trailing spaces
		VgName=$(echo "$VgName" | xargs)
		LvName=$(echo "$LvName" | xargs)
		Size=$(echo "$Size" | xargs)
		FsType=$(echo "$FsType" | xargs)
		Striped=$(echo "$Striped" | xargs)
		Mountpoint=$(echo "$Mountpoint" | xargs)

		LV_VAR+="$VgName"$'\t'"$LvName"$'\t'"$Size"$'\t'"$FsType"$'\t'"$Striped"$'\t'"$Mountpoint"$'\n'
	done < <(tail -n +2 "$LV_FILE")
	# Remove empty lines
	LV_VAR=$(echo "$LV_VAR" | sed '/^$/d')

	while IFS=$'\t' read -r DeviceName VG; do
		volume_groups["$VG"]+="/dev/$DeviceName "
	done < <(echo "$VG_VAR")

	while IFS=$'\t' read -r VgName LvName Size FsType Striped Mountpoint; do
		vg_lvs["$VgName"]+="$LvName "
	done < <(echo "$LV_VAR")

}

perform_prechecks() {
	print_line "Executing prechecks..."

	# Find empty values on VG conf
	while IFS=$'\t' read -r DeviceName VG; do
		[[ -z "$DeviceName" || -z "$VG" ]] && {
			echo "Found empty values on VG conf. Exiting..."
			exit 1
		}
	done < <(echo "$VG_VAR")
	echo "No empty values found for VG conf..."

	MOUNTS_VAR="$(df -ha | awk -F' ' '{print $6}')"
	LSBLK_VAR="$(lsblk | grep -i '\[swap\]')"

	while IFS=$'\t' read -r VgName LvName Size FsType Striped Mountpoint; do
		# Find empty values on VG conf
		[[ -z "$VgName" || -z "$LvName" || -z "$Size" || -z "$FsType" || -z "$Striped" || -z "$Mountpoint" ]] && {
			echo "Found empty values on LV conf. Exiting..."
			exit 1
		}
		# Find invalid fs types
		[[ "$FsType" != 'xfs' && "$FsType" != 'ext4' && "$FsType" != 'ext3' && "$FsType" != 'swap' ]] && {
			echo "Found invalid FS types ($LvName -- $FsType). Exiting..."
			exit 1
		}
		# Find VG references in LV conf that are not present in VG conf
		echo "$VG_VAR" | awk -F$'\t' '{print $2}' | grep -q $VgName || {
			echo "Found LVs that are part of VGs that are not present in VG conf ($LvName). Exiting..."
			exit 1
		}
		# Find currenly mounted filesystems on the targeted paths
		if [ "$DRY_RUN" == 'false' ]; then
			if [ "$FsType" != 'swap' ]; then
				echo "$MOUNTS_VAR" | grep -qE "^$Mountpoint$" && {
					echo "Found currently mounted filesystems on one of the target directories ($Mountpoint)."
					echo "Execute umount $Mountpoint and rerun."
					exit -1
				}
			else
				echo "$LSBLK_VAR" | grep -qE -i "^└─$VgName-$LvName" && {
					echo "Found currently used filesystems as swap ($VgName/$LvName)."
					echo "Execute swapoff -v /dev/$VgName/$LvName and rerun."
					exit -1
				}
			fi
		fi
	done < <(echo "$LV_VAR")
	echo "No empty values found for LV conf..."
	echo "FS types are valid..."
	echo "All VG references are valid..."
	echo "No existing filesystems found mounted on the target direcotries..."

	# Checking for invalid device names
	DEV_VAR="$(lsblk | grep disk | awk -F' ' '{print $1}')"
	while IFS=$'\t' read -r DeviceName VG; do
		echo "$DEV_VAR" | grep -qE "^$DeviceName$" || {
			echo "Found non-existing devices on VG conf ($DeviceName). Exiting..."
			exit 1
		}
	done < <(echo "$VG_VAR")
	echo "All devices in VG conf are valid..."

	echo
	echo "The following lines will be removed from fstab:"
	LNS_TO_REMOVE=''
	MOUNTPOINTS_VAR="$(echo "$LV_VAR" | awk -F$'\t' '{print $6}')"
	while IFS=$'\t' read -r mountpoint; do
		LN_ADDED=$(cat /etc/fstab | grep " $mountpoint ")
		[ "$LN_ADDED" != '' ] && LNS_TO_REMOVE=$(printf "%s\n%s" "$LNS_TO_REMOVE" "  $LN_ADDED")
	done < <(echo "$MOUNTPOINTS_VAR")
	echo "$LNS_TO_REMOVE"
}

create_pvs() {
	print_line "PV Section"

	[ "$FORCE" == 'true' ] && {
		forceFlag='-ff'
	} || forceFlag=''

	while IFS=$'\t' read -r DeviceName VG; do
		# Remove leading/trailing spaces
		DeviceName=$(echo "$DeviceName" | xargs)
		VG=$(echo "$VG" | xargs)

		# Construct and execute the pvcreate command
		cmd_handle "pvcreate $forceFlag /dev/$DeviceName"
	done < <(echo "$VG_VAR")
}

create_vgs() {
	print_line "VG Section"
	# Iterate through each VG group and create the vgcreate command
	for VG in "${!volume_groups[@]}"; do
		devices=${volume_groups["$VG"]}

		# Create and run the vgcreate command for this VG
		cmd_handle "vgcreate $VG $devices"
	done
}

create_lvs() {
	print_line "LV Section"

	[ "$FORCE" == 'true' ] && {
		forceFlag='-y'
	} || forceFlag=''

	# Now iterate over the VG and LV groups to create LVs
	while IFS=$'\t' read -r VgName LvName Size FsType Striped Mountpoint; do
		# Determine if this LV is the last one for its VG
		lvs_for_vg=${vg_lvs["$VgName"]}                   # Get list of LVs for the current VG
		last_lv=$(echo "$lvs_for_vg" | awk '{print $NF}') # Get the last LV in the list

		# If this LV is the last one for this VG, use -l +100%FREE
		if [[ "$LvName" == "$last_lv" ]]; then
			if [[ "$Striped" != "no" ]]; then
				stripes="$(echo $Striped | awk -F'<>' '{print $1}')"
				stripesize="$(echo $Striped | awk -F'<>' '{print $2}')"
				cmd_handle "lvcreate $forceFlag -n $LvName -l +100%FREE --stripes $stripes --stripesize $stripesize $VgName"
			else
				cmd_handle "lvcreate $forceFlag -n $LvName -l +100%FREE $VgName"
			fi
		else
			# Otherwise, use -L <Size_Value>
			if [[ "$Striped" != "no" ]]; then
				stripes="$(echo $Striped | awk -F'<>' '{print $1}')"
				stripesize="$(echo $Striped | awk -F'<>' '{print $2}')"
				cmd_handle "lvcreate $forceFlag -n $LvName -L $Size --stripes $stripes --stripesize $stripesize $VgName"
			else
				cmd_handle "lvcreate $forceFlag -n $LvName -L $Size $VgName"
			fi
		fi
	done < <(echo "$LV_VAR")
}

create_filesystems() {
	print_line "Filesystem Section"

	[ "$FORCE" == 'true' ] && {
		forceFlag='-f'
	} || forceFlag=''

	while IFS=$'\t' read -r VgName LvName Size FsType Striped Mountpoint; do
		if [ "$FsType" == 'swap' ]; then
			cmd_handle "mkswap /dev/$VgName/$LvName"
		else
			[ "$FsType" != 'xfs' ] && forceFlag=''
			cmd_handle "mkfs.$FsType $forceFlag /dev/$VgName/$LvName"
		fi
	done < <(echo "$LV_VAR")
}

create_mountpoints() {
	print_line "Mountpoint Section"
	while IFS=$'\t' read -r VgName LvName Size FsType Striped Mountpoint; do
		[ ! -d "$Mountpoint" ] && [ "$FsType" != 'swap' ] && {
			cmd_handle "mkdir -p $Mountpoint"
		}
	done < <(echo "$LV_VAR")
}

modify_fstab() {
	print_line "Fstab Section"
	while IFS=$'\t' read -r VgName LvName Size FsType Striped Mountpoint; do
		escaped_Mountpoint=$(echo "$Mountpoint" | sed 's/\//\\\//g')
		cmd_handle "sed -i \"/$escaped_Mountpoint /d\" /etc/fstab"

		mountedDevice="/dev/$VgName/$LvName"
		cmd_handle "echo \"$mountedDevice $Mountpoint $FsType defaults 0 0\" >> /etc/fstab"

	done < <(echo "$LV_VAR")
}

perform_mount_all() {
	print_line "Mount Section"
	cmd_handle "mount -a"
	cmd_handle "swapon -av"
	echo
}

reset_unmount_fs() {
	print_line "Unmount Section"
	while IFS=$'\t' read -r VgName LvName Size FsType Striped Mountpoint; do
		if [ "$FsType" != 'swap' ]; then
			cmd_handle "umount $Mountpoint"
		else
			cmd_handle "swapoff -v /dev/$VgName/$LvName"
		fi
	done < <(echo "$LV_VAR")
}

reset_remove_lvs() {
	print_line "Remove LV Section"
	while IFS=$'\t' read -r VgName LvName Size FsType Striped Mountpoint; do
		cmd_handle "lvremove -y $VgName/$LvName"
	done < <(echo "$LV_VAR")
}

reset_remove_vgs() {
	print_line "Remove VG Section"
	while IFS=$'\t' read -r VgName; do
		cmd_handle "vgremove -y $VgName"
	done < <(echo "$VG_VAR" | awk -F$'\t' '{print $2}' | sort | uniq)
}

reset_remove_pvs() {
	print_line "Remove PV Section"
	while IFS=$'\t' read -r PvName; do
		cmd_handle "pvremove -y /dev/$PvName"
	done < <(echo "$VG_VAR" | awk -F$'\t' '{print $1}' | sort | uniq)
}

reset_modify_fstab() {
	print_line "Fstab Section"
	while IFS=$'\t' read -r VgName LvName Size FsType Striped Mountpoint; do
		escaped_Mountpoint=$(echo "$Mountpoint" | sed 's/\//\\\//g')
		cmd_handle "sed -i \"/$escaped_Mountpoint /d\" /etc/fstab"
	done < <(echo "$LV_VAR")
}

init_args "$@"
