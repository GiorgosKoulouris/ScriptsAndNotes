# attaches/detaches secondary IPs on ENIs

# IAM permissions
:'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:AssignPrivateIpAddresses",
        "ec2:UnassignPrivateIpAddresses",
        "ec2:DescribeNetworkInterfaces"
      ],
      "Effect": "Allow",
      "Resource": [
        "arn:aws:ec2:ue-central-1:339712771459:network-interface/eni-02d016de5a9c64db0",
        "arn:aws:ec2:ue-central-1:339712771459:network-interface/eni-0c0fabb03554ce322"
        ]
    },
        {
      "Action": [
        "ec2:DescribeNetworkInterfaces"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
'

# On each node
[ -d /scripts/pacemaker/ ] || mkdir -p /scripts/pacemaker/
[ -d /usr/lib/ocf/resource.d/custom/ ] || mkdir -p /usr/lib/ocf/resource.d/custom/

vi /scripts/pacemaker/aws_vip # OCF File
vi /scripts/pacemaker/aws_vip_actions.sh # aws_vip_actions.sh File
chmod +x /scripts/pacemaker/aws_vip
chmod +x /scripts/pacemaker/aws_vip_actions.sh

ln -s /scripts/pacemaker/aws_vip /usr/lib/ocf/resource.d/custom/aws_vip


# On cluster
crm configure primitive db_vip ocf:custom:aws_vip \
    params ip_address="10.0.10.80" \
    if_name=auto \
    op start interval=0s timeout=60s \
    op stop interval=0s timeout=40s \
    op monitor interval=10s timeout=10s \
    meta allow-migrate=true target-role=Started

# OR
pcs resource create db_vip ocf:custom:aws_vip \
    ip_address=10.0.10.80 \
    if_name=auto \
    op start interval=0s timeout=60s \
    op stop interval=0s timeout=40s \
    op monitor interval=10s timeout=10s \
    meta allow-migrate=true target-role=Started

pcs constraint colocation add db_vip with tcopdb-clone INFINITY
pcs constraint remove db_vip

crm resource refresh
crm ra info ocf:custom:aws_vip

crm configure colocation vip_on_drbd inf: aws_vip drbd_r0_cl:Master
crm configure order vip_after_drbd inf: drbd_r0_cl:promote aws_vip:start