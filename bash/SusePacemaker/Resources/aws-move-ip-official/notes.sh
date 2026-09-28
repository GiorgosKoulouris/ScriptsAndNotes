# attaches/detaches secondary IPs on ENIs
# https://docs.aws.amazon.com/sap/latest/sap-AnyDB/sap-ibm-pacemaker-deployment.html

# IAM permissions
:'
{
  "Version": "2012-10-17",
  "Statement": [

    {
      "Sid": "AllowDescribe",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeRouteTables"
      ],
      "Resource": "*"
    },

    {
      "Sid": "AllowAssignSpecificPrivateIP",
      "Effect": "Allow",
      "Action": [
        "ec2:AssignPrivateIpAddresses",
        "ec2:UnassignPrivateIpAddresses"
      ],
      "Resource": [
        "arn:aws:ec2:eu-central-1:339712771459:network-interface/eni-009ab8e1bdfa10052",
        "arn:aws:ec2:eu-central-1:339712771459:network-interface/eni-0e8bd4162744d7189"
      ]
    },

    {
      "Sid": "AllowRouteChangeSpecificRTB",
      "Effect": "Allow",
      "Action": [
        "ec2:ReplaceRoute"
      ],
      "Resource": "arn:aws:ec2:eu-central-1:339712771459:route-table/rtb-07e9d77ab35a7519f"
    }

  ]
}
'

mkdir -p /lib/heartbeat
ln -s /usr/lib/ocf/lib/heartbeat/ocf-shellfuncs /lib/heartbeat/ocf-shellfuncs

# On cluster (IP must not be in subnet range)
crm configure primitive rsc_ip_HDS_HDB00 ocf:heartbeat:aws-vpc-move-ip \
  params ip=10.249.0.5 interface=eth0 \
  region=eu-central-1 \
  routing_table=rtb-07e9d77ab35a7519f \
  auth_type=role \
  op start timeout=180s \
  op stop timeout=180s \
  op monitor interval=60s timeout=60s

crm configure colocation ip_with_primary 2000: rsc_ip_HDS_HDB00 msl_SAPHana_HDS_HDB00:Master