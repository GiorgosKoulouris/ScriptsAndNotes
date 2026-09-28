# Role permissions
:'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DescribePermissions",
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeAddresses",
                "ec2:DescribeInstances",
                "ec2:DisassociateAddress"
            ],
            "Resource": "*"
        },
        {
            "Sid": "AllowAssociateSpecificEIP",
            "Effect": "Allow",
            "Action": "ec2:AssociateAddress",
            "Resource": "*"
        }
    ]
}
'

mkdir -p /usr/lib/ocf/resource.d/custom/

vi /usr/lib/ocf/resource.d/custom/aws_vip
chmod x /usr/lib/ocf/resource.d/custom/aws_vip

crm configure primitive aws_vip ocf:custom:aws_vip \
        params eni_id=eni-075316474fb4fdd54 \
        op start interval=0s timeout=60s \
        op stop interval=0s timeout=40s \
        op monitor interval=10s timeout=10s \
        meta target-role=Started

crm resource refresh
crm ra info ocf:custom:aws_vip

crm configure colocation vip_on_drbd inf: aws_vip drbd_r0_cl:Master
crm configure order vip_after_drbd inf: drbd_r0_cl:promote aws_vip:start