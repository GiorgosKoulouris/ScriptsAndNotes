zypper addrepo https://download.opensuse.org/repositories/network:ha-clustering:Stable/15.6/network:ha-clustering:Stable.repo
zypper ref
zypper in crmsh hawk2

echo softdog > /etc/modules-load.d/watchdog.conf
systemctl restart systemd-modules-load

crm cluster init --name awscluster

# Temporarily enable root login and password login until the other node is joined
# Then disable

https://10.24.24.103:7630/


zypper install MariaDB-server MariaDB-client galera-4

/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_vol0fc369840d3aa3c49
