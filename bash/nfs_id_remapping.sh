mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport fs-066a308fc03a09346.efs.eu-central-1.amazonaws.com:/ /mnt

groupadd sp1sys
useradd -g sp1sys -s /bin/bash -m sp1adm

groupadd sp2sys
useradd -g sp2sys -s /bin/bash -m sp2adm


id sp1adm # -->uid=1002(sp1adm) gid=1002(sp1sys) groups=1002(sp1sys)
id sp2adm # --> uid=1003(sp2adm) gid=1003(sp2sys) groups=1003(sp2sys)

cd /mnt
mkdir t1
mkdir t2
mkdir t1/tt1
mkdir t1/tt2
mkdir t2/tt1
mkdir t2/tt2

chown -R sp1adm:sp1sys /mnt

:'
[root@tcoptnfs00 mnt]# ls -l /mnt/
total 8
drwxr-xr-x. 4 sp1adm sp1sys 6144 Oct  9 20:44 t1
drwxr-xr-x. 4 sp1adm sp1sys 6144 Oct  9 20:44 t2
'

# Install bindfs
yum install gcc gcc-c++ make fuse3-devel git autoconf fuse3 automake

cd /usr/local/src
git clone https://github.com/mpartel/bindfs.git
./autogen.sh  # Only needed if you cloned the repo.
./configure
make
make install

mkdir /remapped

# The following creates a bind of the already nfs mounted /mnt to /remapped
# changing the ownership from sp1adm:sp1sys (1002:1002) to sp2adm:sp2sys (1003:1003)
/usr/local/bin/bindfs -u 1003 -g 1003 /mnt/ /remapped

:'
[root@tcoptnfs00 ~]# df -hT | grep -E "(^File|mnt|remap)"
Filesystem                                            Type         Size  Used Avail Use% Mounted on
fs-066a308fc03a09346.efs.eu-central-1.amazonaws.com:/ nfs4         8.0E     0  8.0E   0% /mnt
/mnt                                                  fuse.bindfs  8.0E     0  8.0E   0% /remapped

[root@tcoptnfs00 ~]# ls -l /mnt/
total 8
drwxr-xr-x. 4 sp1adm sp1sys 6144 Oct  9 20:44 t1
drwxr-xr-x. 4 sp1adm sp1sys 6144 Oct  9 20:44 t2

[root@tcoptnfs00 ~]# ls -l /remapped/
total 8
drwxr-xr-x. 4 sp2adm sp2sys 6144 Oct  9 20:44 t1
drwxr-xr-x. 4 sp2adm sp2sys 6144 Oct  9 20:44 t2
'
