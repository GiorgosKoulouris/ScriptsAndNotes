:'
OVERVIEW
  - Create a helper with same OS

  - Create a copy (source) of the source OS and attach on the helper

  - Create a new disk (target) based on the target size and attach on the helper
      For Azure:
        az disk create --resource-group rgName --name newOsDiskName --size-gb sizeInGB --sku Standard_LRS --os-type Linux --security-type TrustedLaunch --hyper-v-generation V2

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
newDisk=sdc # Change accordingly
spacerSizeMB=1
bootSizeMB=800 # in MB
rootSizeMB=7000 # in MB. Example: for 4GB use 4000, not 4096)
efiSizeMB=99 # in MB

blocksize=$(cat /sys/block/$newDisk/queue/hw_sector_size)
sectors=$(cat /sys/block/$newDisk/size)

# The following needs to be modified based on source disk (for example if there is a seperate boot partition, spacers, efi. Sequence must be followed)
# This example has a spacer on p1, boot on p2 and root on p3
spacerSectors=$(echo "$spacerSizeMB * 1024 * 1024 / $blocksize" | bc)
rootSectors=$(echo "$rootSizeMB * 1024 * 1024 / $blocksize" | bc)
efiSectors=$(echo "$efiSizeMB * 1024 * 1024 / $blocksize" | bc)
bootSectors=$(echo "$bootSizeMB * 1024 * 1024 / $blocksize" | bc)

# Start layout
start1=2048
end1=$(echo "$start1 + $spacerSectors - 1" | bc)
start2=$(echo "$end1 + 1" | bc)
end2=$(echo "$start2 + $bootSectors - 1" | bc)
start3=$(echo "$end2 + 1" | bc)
end3=$(echo "$start3 + $rootSectors - 1" | bc)
start4=$(echo "$end3 + 1" | bc)
end4=$(echo "$start4 + $spacerSectors - 1" | bc)
start5=$(echo "$end4 + 1" | bc)
end5=$(echo "$start5 + $efiSectors - 1" | bc)
# Final check: end3 < total sectors?
if (( end5 > sectors )); then
  echo "ERROR: Partition plan exceeds disk size!" >&2
else
  echo "Partition layout is valid:"
  echo "  boot:   $start1 - $end1"
  echo "  efi: $start2 - $end2"
  echo "  root:    $start3 - $end3"
fi

sgdisk -p /dev/sda # Execute this on source Disk to get the partition types

# Wipe disk first (be careful)
sgdisk --zap-all /dev/$newDisk
# Create spacer for this example (Partition 1)
sgdisk --new=1:$start1:$end1 --typecode=1:8300 /dev/$newDisk
# Create boot for this example (Partition 2)
sgdisk --new=2:$start2:$end2 --typecode=2:8300 /dev/$newDisk
# Create root for this example (Partition 3)
sgdisk --new=3:$start3:$end3 --typecode=3:8E00 /dev/$newDisk

sgdisk --new=5:$start5:$end5 --typecode=5:0700 /dev/$newDisk
# To verify
sgdisk -p /dev/$newDisk


# ------------- Filesystems ------------------
# In this example the source disk was nvme1n1 and the target nvme2n1 (p1: spacer, p2: boot, p3: root ) (you may need to create/mount differently if there is EFI etc)
mkfs.xfs /dev/sdc1
mkfs.xfs /dev/sdc2
mkdir /mnt/newroot
mount /dev/vgroot/root /mnt/newroot
mkdir /mnt/newroot/boot
mount /dev/sdc2 /mnt/newroot/boot/
mkdir /mnt/newroot/boot/efi
mount /dev/sdc5 /mnt/newroot/boot/efi

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
  --exclude="media/*" / /mnt/newroot/

# For boot
rsync -avox /boot/ /mnt/newroot/boot/

rsync -avox /boot/efi/ /mnt/newroot/boot/efi/ 

# ------------- Grub configuration ------------------
# Create temp bind mounts
for d in dev proc sys; do mkdir /$d; mount --bind /$d /mnt/newroot/$d; done
# Change root
chroot /mnt/newroot

# Modify FSTAB accordingly
# Modify kernel boot options accordingly (/etc/default/grub and grubby --update-kernel=ALL --args="XXXXXXX")

echo "GRUB_DISABLE_OS_PROBER=true" >> /etc/default/grub
# Recreate the config
grub2-mkconfig -o /boot/grub2/grub.cfg
# Also this for EFI (path varies based on distro)
grub2-mkconfig -o /boot/efi/EFI/oracle/grub.cfg

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
ls (hd0,gpt2)/

# This will set the BOOT to the correct drive/partition (modify accrodingly)
set root=(hd0,gpt2)/ # point it to boot FS
# This will point grub to the grub installation (modify accrodingly)
set prefix=(hd0,gpt2)/grub2

# After setting the variables, execute the following to boot
insmod normal
insmod lvm
insmod linux

# Load the kernel from the /boot partition
linux (hd0,gpt2)/vmlinuz-6.12.0-104.43.4.2.el9uek.x86_64 root=/dev/mapper/vgroot-root ro rhgb quiet
# Load the matching initramfs
initrd (hd0,gpt2)/initramfs-6.12.0-104.43.4.2.el9uek.x86_64.img
# Finally boot
boot

