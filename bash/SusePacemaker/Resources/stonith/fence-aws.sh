#!/bin/bash

yum install fence-agents-aws
pcs stonith list | grep -i aws # or crm ra list stonith | grep -i aws

# IAM policy
:'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "InstanceActions",
            "Effect": "Allow",
            "Action": [
                "ec2:RebootInstances",
                "ec2:StartInstances",
                "ec2:StopInstances"
            ],
            "Resource": [
                "arn:aws:ec2:eu-central-1:339712771459:instance/i-050bac009cf7fa76c",
                "arn:aws:ec2:eu-central-1:339712771459:instance/i-0a161bbd59a5705af"
            ]
        },
        {
            "Sid": "InstanceInfo",
            "Effect": "Allow",
            "Action": "ec2:DescribeInstances",
            "Resource": "*"
        }
    ]
}
'
# --------------- PCS --------------------
pcs stonith create fence-aws-tcoptcls00 fence_aws \
    pcmk_host_list=tcoptcls00 \
    pcmk_host_check=static-list \
    region=eu-central-1 \
    plug=i-050bac009cf7fa76c \
    power_timeout=240

pcs stonith create fence-aws-tcoptcls01 fence_aws \
    pcmk_host_list=tcoptcls01 \
    pcmk_host_check=static-list \
    region=eu-central-1 \
    plug=i-0a161bbd59a5705af \
    power_timeout=240

pcs stonith enable fence-aws-tcoptcls00
pcs stonith enable fence-aws-tcoptcls01

pcs resource ban fence-aws-tcoptcls00 tcoptcls00
pcs resource ban fence-aws-tcoptcls01 tcoptcls01
# Or 
pcs constraint location stonith_tcopthds00 avoids tcopthds00=INFINITY
pcs constraint --full

pcs property set no-quorum-policy=ignore # safe for 2-node clusters
pcs property set stonith-enabled=true

# Actual test
pcs stonith fence tcoptcls01
# To clean stonith/fencing history
pcs stonith history cleanup
# Simulate to check fencing
pcs cluster stop tcoptcls01

# --------------- CRM --------------------
crm configure primitive stonith_tcopthds00 stonith:fence_aws \
    pcmk_host_list=tcopthds00 \
    pcmk_host_check=static-list \
    region=eu-central-1 \
    plug=i-011704f201c6bf0ec \
    power_timeout=240 \
    pcmk_delay_max="30s"

crm configure primitive stonith_tcopthds01 stonith:fence_aws \
    pcmk_host_list=tcopthds01 \
    pcmk_host_check=static-list \
    region=eu-central-1 \
    plug=i-031776ab0637b2644 \
    power_timeout=240 \
    pcmk_delay_max="30s"


crm configure location no_stonith_on_tcopthds00 stonith_tcopthds00 -inf: tcopthds00
crm configure location no_stonith_on_tcopthds01 stonith_tcopthds01 -inf: tcopthds01

# Test with the fence agent directly
fence_aws \
  --plug=i-011704f201c6bf0ec \
  --region=eu-central-1 \
  --action=status \
  --verbose

# Troubleshoot
journalctl -xe | grep fence