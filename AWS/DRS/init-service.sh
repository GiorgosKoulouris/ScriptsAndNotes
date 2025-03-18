cat >agent-source-drs-trust-policy.json <<EOF
{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Effect": "Allow",
			"Principal": {
				"Service": "drs.amazonaws.com"
			},
			"Action": [
				"sts:AssumeRole",
				"sts:SetSourceIdentity"
			],
			"Condition": {
				"StringLike": {
					"sts:SourceIdentity": "s-*",
					"aws:SourceAccount": "1234567891011"
				}
			}
		}
	]
}
EOF

aws iam create-role --path "/service-role/" --role-name \
	AWSElasticDisasterRecoveryAgentRole --assume-role-policy-document file://agent-source-drs-trust-policy.json

cat >failback-source-drs-trust-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "drs.amazonaws.com"
            },
            "Action": [
                "sts:AssumeRole",
                "sts:SetSourceIdentity"
            ],
            "Condition": {
                "StringLike": {
                    "aws:SourceAccount": "1234567891011",
                    "sts:SourceIdentity": "i-*"
                }
            }
        }
    ]
}
EOF

aws iam create-role --path "/service-role/" --role-name \
    AWSElasticDisasterRecoveryFailbackRole --assume-role-policy-document file://failback-source-drs-trust-policy.json

cat >source-drs-trust-policy.json <<EOF
{
    "Version":  "2012-10-17",
     "Statement": [
        {
             "Effect":  "Allow",
             "Principal": {
                 "Service":  "ec2.amazonaws.com"
            },
             "Action":  "sts:AssumeRole"
        }
    ]
}
EOF

aws iam create-role --path "/service-role/" --role-name \
    AWSElasticDisasterRecoveryConversionServerRole --assume-role-policy-document file://source-drs-trust-policy.json

aws iam create-role --path "/service-role/" --role-name \
    AWSElasticDisasterRecoveryRecoveryInstanceRole --assume-role-policy-document file://source-drs-trust-policy.json

aws iam create-role --path "/service-role/" --role-name \
    AWSElasticDisasterRecoveryReplicationServerRole --assume-role-policy-document file://source-drs-trust-policy.json

aws iam attach-role-policy \
    --role-name AWSElasticDisasterRecoveryAgentRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSElasticDisasterRecoveryAgentPolicy

aws iam attach-role-policy \
    --role-name AWSElasticDisasterRecoveryFailbackRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSElasticDisasterRecoveryFailbackPolicy

aws iam attach-role-policy \
    --role-name AWSElasticDisasterRecoveryConversionServerRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSElasticDisasterRecoveryConversionServerPolicy

aws iam attach-role-policy \
    --role-name AWSElasticDisasterRecoveryRecoveryInstanceRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSElasticDisasterRecoveryRecoveryInstancePolicy

aws iam attach-role-policy \
    --role-name AWSElasticDisasterRecoveryReplicationServerRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSElasticDisasterRecoveryReplicationServerPolicy
