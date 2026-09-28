# Docs
# https://documentation.suse.com/sle-ha/15-SP6/html/SLE-HA-all/cha-ha-storage-protect.html

rpm -ql "$(uname -r)" | grep watchdog

lsmod | egrep "(wd|dog)"
rmmod WRONG_MODULE
echo WATCHDOG_MODULE > /etc/modules-load.d/watchdog.conf # EG softdog
systemctl restart systemd-modules-load
lsmod | grep dog
ls -l /dev/watchdog*
sbd query-watchdog
sbd -w /dev/watchdog test-watchdog

ls -l /dev/disk/by-id
sbd -d /dev/disk/by-id/DEVICE_ID create
sbd -d /dev/disk/by-id/DEVICE_ID dump
sbd -d /dev/disk/by-id/DEVICE_ID list
sbd -w /dev/disk/by-id/DEVICE_ID test-watchdog


vi /etc/sysconfig/sbd
crm configure property no-quorum-policy=ignore
crm configure property stonith-enabled="true"
crm configure property stonith-watchdog-timeout="20s"
crm configure property stonith-timeout="40s"

crm configure primitive stonith_sbd stonith:external/sbd \
  params pcmk_delay_max="30s"

