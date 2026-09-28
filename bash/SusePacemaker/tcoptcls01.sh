zypper addrepo https://download.opensuse.org/repositories/network:ha-clustering:Stable/15.6/network:ha-clustering:Stable.repo
zypper ref
zypper in crmsh
zypper in hawk2

echo softdog > /etc/modules-load.d/watchdog.conf
systemctl restart systemd-modules-load

# Temporarily enable root login and password login until you join to the cluster
# Then disable
crm cluster join
sbd -d /dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_vol0fc369840d3aa3c49 list

zypper install MariaDB-server MariaDB-client galera-4

