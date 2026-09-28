:"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeTags"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:StopInstances",
        "ec2:StartInstances"
      ],
      "Resource": "*"
    }
  ]
}
"

# Create custom aws profile
aws configure --profile cluster # for role based leave access and secret keys empty

# tag must be an EC2 instance tag with the value being the hostname
# for example: hdscluster: hostname means that tag parameter is "hdscluster"
crm configure primitive res_stonith stonith:external/ec2 \
    params tag="hdscluster" profile="cluster" \
    pcmk_delay_max="10" \
    op start interval="0" timeout="180" \
    op stop interval="0" timeout="180" \
    op monitor interval="300" timeout="60"

# Tests
#   https://docs.aws.amazon.com/sap/latest/sap-hana/sap-hana-pacemaker-sles-testing.html

# Stop HANA on the primary node using HDB kill-9
HDB kill-9

# Simulate a hardware failure
# On primary
poweroff --force --force

# Simulate a kernel panic
echo 'c' > /proc/sysrq-trigger

# Cleanup
stonith_admin --cleanup --history tcopthds01