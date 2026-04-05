yum install -y samba samba-client samba-common

useradd -M -s /sbin/nologin smbuser
smbpasswd -a smbuser
smbpasswd -e smbuser
mkdir -p /tmp/smbshare
chown -R smbuser:smbuser /tmp/smbshare
chmod -R 0770 /tmp/smbshare


vi /etc/samba/smb.conf

:'
[global]
   workgroup = WORKGROUP
   security = user
   server string = Oracle Linux SMB Server
   map to guest = never
   smb ports = 445
   log file = /var/log/samba/%m.log
   max log size = 1000

[smbshare]
   path = /tmp/smbshare
   browseable = yes
   writable = yes
   valid users = smbuser
   force user = smbuser
   force group = smbuser
   create mask = 0660
   directory mask = 0770
'
systemctl enable --now smb nmb

# ----- Client -----
yum install -y cifs-utils
mkdir -p /mnt/smbshare

vi /root/.smbcredentials
:'
username=smbuser
password=atP87X68k2kk7Q2GQc42
'
chmod 600 /root/.smbcredentials

# FSTAB
:'
//10.160.38.15/smbshare/interfaces  /mnt/interfaces cifs  nofail,credentials=/root/.smbcredentials,serverino,dir_mode=0750,nosharesock,actimeo=30,_netdev  0  0
//10.160.38.15/smbshare/home        /mnt/home       cifs  nofail,credentials=/root/.smbcredentials,serverino,dir_mode=0750,nosharesock,actimeo=30,_netdev  0  0
'

/mnt/interfaces/interface1 /mnt/home/user1/inter1 none bind,nofail,noatime,x-systemd.requires-mounts-for=/mnt/home,x-systemd.requires-mounts-for=/mnt/interfaces 0 0
/mnt/interfaces/interface2 /mnt/home/user2/inter2 none bind,nofail,noatime,x-systemd.requires-mounts-for=/mnt/home,x-systemd.requires-mounts-for=/mnt/interfaces 0 0

/mnt/interfaces/interface1 /mnt/home/user1/inter1 none bind
/mnt/interfaces/interface2 /mnt/home/user2/inter2 none bind

