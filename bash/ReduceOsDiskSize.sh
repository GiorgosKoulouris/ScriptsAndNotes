:'
OVERVIEW
  - Create a helper with same OS

  - Create a copy (source) of the source OS and attach on the helper

  - Create a new disk (target) based on the target size and attach on the helper

  - If the source disk/partitions/FS have the same UUID as the OS disk on the helper, relabel and change UUIDs (note the initial values) >> Section: FS Relabeling

  - On the target disk, replicate the GPT partition table. Sizes for spacers, EFI, boot should remain the same. Root size will be the target size >> Section: Disk Partitioning

  - Create the filesystems on the new disk/paritions (follow the format of the source XFS, vfat etc) >> Section: Filesystems

  - Mount the new and old root drives/partitions on the helper >> Section: Filesystems
      suggested starting mountpoints:
        source root > /mnt/oldroot
        target root > /mnt/newroot

  - rsync old filesystems to new ones (rsync all seperately) >> Section: RSYNC

  - Grub configuration >> Section: Grub configuration
      Make the temp mounts (proc, sys etc.) on the new root mountpoint tree
      chroot to new root
      Install grub on the device, modify grub config and create grub.cfg
      Verify that kernels, configs and menuentries exist. Verify the selected kernel.
      Verify that boot options for the kernel have the correct device ID for root
      Verify fstab. This should be modified to have the new disk UUIDs

  - Detach the new OS disk and attach on original machine

  - Boot
  - Check this section for grub related commands (console) if you face any issues >> Section: Grub console
'

# ------------- FS Relabeling ------------------
# Identify current FS types, labels and UUIDs
blkid

# Change XFS UUID/Label
xfs_admin -L oldroot -U "$(uuidgen)" /dev/nvme1n1p3 # For XFS - change the device accordingly (replace uuidgen with existing to revert)
tune2fs -L 'oldroot' -U "$(uuidgen)" /dev/nvme1n1p3 # For EXT - change the device accordingly (replace uuidgen with existing to revert)
mlabel -N 5A01AD98 -i /dev/nvme1n1p128 ::oldefi # For VFAT - change the device accordingly (this leads to UUID 5A01-AD98)


# ------------- Disk Partitioning ------------------
newDisk=nvme2n1 # Change accordingly
rootSizeMB=15000 # in MB. Example: for 4GB use 4000, not 4096)
spacerSizeMB=1 # in MB
bootSizeMB=1000 # in MB

blocksize=$(cat /sys/block/$newDisk/queue/hw_sector_size)
sectors=$(cat /sys/block/$newDisk/size)

# The following needs to be modified based on source disk (for example if there is a seperate boot partition, spacers, efi. Sequence must be followed)
# This example has a spacer on p1, boot on p2 and root on p3
rootSectors=$(echo "$rootSizeMB * 1024 * 1024 / $blocksize" | bc)
spacerSectors=$(echo "$spacerSizeMB * 1024 * 1024 / $blocksize" | bc)
bootSectors=$(echo "$bootSizeMB * 1024 * 1024 / $blocksize" | bc)

# Start layout
start1=2048
end1=$(echo "$start1 + $spacerSectors - 1" | bc)
start2=$(echo "$end1 + 1" | bc)
end2=$(echo "$start2 + $bootSectors - 1" | bc)
start3=$(echo "$end2 + 1" | bc)
end3=$(echo "$start3 + $rootSectors - 1" | bc)

# Final check: end3 < total sectors?
if (( end3 > sectors )); then
  echo "ERROR: Partition plan exceeds disk size!" >&2
else
  echo "Partition layout is valid:"
  echo "  root:   $start1 - $end1"
  echo "  spacer: $start2 - $end2"
  echo "  efi:    $start3 - $end3"
fi

sgdisk -p /dev/nvme1n1 # Execute this on source Disk to get the partition types

# Wipe disk first (be careful)
sgdisk --zap-all /dev/$newDisk
# Create spacer for this example (Partition 1)
sgdisk --new=1:$start1:$end1 --typecode=1:EF02 /dev/$newDisk
# Create boot for this example (Partition 2)
sgdisk --new=2:$start2:$end2 --typecode=2:EA00 /dev/$newDisk
# Create root for this example (Partition 3)
sgdisk --new=3:$start3:$end3 --typecode=3:8300 /dev/$newDisk
# To verify
sgdisk -p /dev/$newDisk


# ------------- Filesystems ------------------
# In this example the source disk was nvme1n1 and the target nvme2n1 (p1: spacer, p2: boot, p3: root ) (you may need to create/mount differently if there is EFI etc)
mkfs.xfs /dev/nvme2n1p2
mkfs.xfs /dev/nvme2n1p3
mkdir /mnt/newroot
mkdir /mnt/newroot/boot
mount /dev/nvme2n1p3 /mnt/newroot
mount /dev/nvme2n1p2 /mnt/newroot/boot/

mkdir /mnt/oldroot
mkdir /mnt/oldroot/boot
mount /dev/nvme1n1p3 /mnt/oldroot
mount /dev/nvme1n1p2 /mnt/oldroot/boot/

# ------------- RSYNC ------------------
# Change depending on the disks (boot,EFI etc)
# For root
rsync -avox \
  --exclude="proc/*" \
  --exclude="sys/*" \
  --exclude="dev/*" \
  --exclude="tmp/*" \
  --exclude="run/*" \
  --exclude="mnt/*" \
  --exclude="media/*" /mnt/oldroot/ /mnt/newroot/

# For boot
rsync -avox /mnt/oldboot/boot/ /mnt/newroot/boot/

# ------------- Grub configuration ------------------
# Create temp bind mounts
for d in dev proc sys; do mkdir /mnt/newroot/$d; mount --bind /$d /mnt/newroot/$d; done
# Change root
chroot /mnt/newroot
# Install grub on new disk (modify accordingly)
grub2-install /dev/nvme2n1
## SKIP FOR NOW
# Or for EFI grub2-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
# Modify /etc/default/grub
echo "GRUB_DISABLE_OS_PROBER=true" >> /etc/default/grub
# Recreate the config
grub2-mkconfig -o /boot/grub2/grub.cfg
# Also this for EFI (path varies based on distro)
grub2-mkconfig -o /boot/efi/EFI/amzn/grub.cfg

# Check that fstab has entries based on the new UUIDs/Labels. Modify according to the new UUIDs
blkid # To get the new UUIDs
vi /etc/fstab # To modify fstab

# Exit chroot and unmount the filesystems
exit
for d in dev proc sys; do umount /mnt/newroot/$d; done
umount /mnt/newroot/boot/
umount /mnt/newroot/


# ------------- Grub console ------------------
# Check entries
ls
# This shows the FS type (modify based on ls output)
ls (hd0,gpt1)
# This shows the FS items/content (modify based on ls output)
ls (hd0,gpt1)/

# This will set the root to the correct drive/partition (modify accrodingly)
set root=(hd0,gpt1)
# This will point grub to the grub installation (modify accrodingly)
set prefix=(hd0,gpt2)/boot/grub2

# After setting the variables, execute the following to boot
insmod normal
normal