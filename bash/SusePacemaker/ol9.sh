# dnf install oraclelinux-developer-release-el9
dnf config-manager --enable ol9_addons ol9_appstream ol9_baseos_latest
dnf groupinstall "High Availability"
dnf install pacemaker pcs corosync resource-agents fence-agents-all
dnf install crmsh
systemctl enable --now pcsd
systemctl enable --now corosync
systemctl enable --now pacemaker

passwd hacluster
# Change SSH to allow SSH password logins
pcs host auth tcoptcls00 tcoptcls01 -u hacluster -p password
pcs cluster setup tcoptcls tcoptcls00 tcoptcls01

pcs cluster start --all
pcs cluster enable --all
pcs status

