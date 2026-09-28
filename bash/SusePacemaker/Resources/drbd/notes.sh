dd if=/dev/zero of=/dev/nvme2n1 count=16 bs=1M

cat <<EOF | tee /etc/drbd.conf
# startup {
#     # wfc-timeout degr-wfc-timeout outdated-wfc-timeout
#     # wait-after-sb;
#     wfc-timeout 100;
#     degr-wfc-timeout 120;
# }
resource r0 { 
  device /dev/drbd0; 
  disk /dev/nvme2n1; 
  meta-disk internal; 
  on tcoptcls02 { 
    address  10.0.10.22:7788;
    node-id 0; 
  }
  on tcoptcls03 { 
    address 10.0.10.26:7788;
    node-id 1; 
  }
  disk {
    resync-rate 10M; 
  }
  connection-mesh { 
    hosts tcoptcls02 tcoptcls03;
  }
  net {
    protocol C; 
    fencing resource-and-stonith; 
   }
  handlers { 
    fence-peer "/usr/lib/drbd/crm-fence-peer.9.sh";
    after-resync-target "/usr/lib/drbd/crm-unfence-peer.9.sh";
   }
}
EOF


# both nodes
drbdadm create-md r0
drbdadm up r0

drbdadm new-current-uuid --clear-bitmap r0/0
drbdadm status
#on one node
drbdadm primary --force r0

mkfs.xfs /dev/drbd0

crm configure edit

primitive drbd_r0 ocf:linbit:drbd \
        params drbd_resource=r0 \
        op monitor interval=15 role=Promoted \
        op monitor interval=30 role=Unpromoted
clone drbd_r0_cl drbd_r0 \
        meta promotable=true promoted-max=1 promoted-node-max=1 clone-max=2 clone-node-max=1 notify=true interleave=true

crm configure primitive fs_drbd0 ocf:heartbeat:Filesystem \
  params device="/dev/drbd0" directory="/mnt/drbd" fstype="xfs" \
  op monitor interval=10s timeout=10s
crm configure colocation fs_on_drbd inf: fs_drbd0 drbd_r0_cl:Master
crm configure order fs_after_drbd inf: drbd_r0_cl:promote fs_drbd0:start

crm resource stop fs_drbd0
crm configure delete fs_drbd0
crm resource stop drbd_r0
crm configure delete drbd_r0
drbdadm down r0
