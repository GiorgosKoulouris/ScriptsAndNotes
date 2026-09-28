#!/bin/bash

envFile="./00_variables.sh"

echo
echo "# ========= Start of CMD sequence ========"
grep -E "(^export EKS_CLUSTER_NAME|^export ACCOUNT_ID|^export REGION|^export IAM_EKS_CLUSTER_ADMIN_ROLE)" "$envFile" | awk -F' ' '{print $2}'

echo

echo 'echo "" >>~/.aws/config'

appendCmd='
cat >>~/.aws/config <<EOF
[profile ${EKS_CLUSTER_NAME}-admin]
region = eu-central-1
output = json
role_arn = arn:aws:iam::${ACCOUNT_ID}:role/${IAM_EKS_CLUSTER_ADMIN_ROLE}
source_profile = default
EOF'

echo "$appendCmd"

echo
echo "# Verify"
echo "cat ~/.aws/config"
echo
echo '# Backup the current config, if any'
echo '[ -f ~/.kube/config ] && mv ~/.kube/config ~/.kube/config.bak'
echo '# Populate the config on the current user'
echo 'aws eks update-kubeconfig --region $REGION --name $EKS_CLUSTER_NAME --profile "$EKS_CLUSTER_NAME-admin"'
echo
echo '# Verify'
echo 'kubectl get nodes'
echo "# ========= End of CMD sequence ========"
