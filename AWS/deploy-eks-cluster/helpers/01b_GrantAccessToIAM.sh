#!/bin/bash

source ./00_variables.sh

print_line() {
  echo
  printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' .
  echo "$1"
  echo
}

verify_status() {
  if [ $? -ne 0 ]; then
    echo "$2. Exiting..."
    [ -f 'policy.json' ] && rm -f 'policy.json'
    exit 1
  else
    echo "$1"
  fi
}

spin() {
  sp='/-\|'
  printf ' '
  while sleep 1; do
    printf '\b%.1s' "$sp"
    sp=${sp#?}${sp%???}
  done
}

print_line "Verifying environment variables.."

[ -z "${EKS_CLUSTER_NAME}" ] && echo "EKS_CLUSTER_NAME is not set" && exit 1 || echo "Cluster Name is set to '${EKS_CLUSTER_NAME}'"
[ -z "${REGION}" ] && echo "REGION is not set" && exit 1 || echo "Region is set to '${REGION}'"
[ -z "${IAM_EXT_USERNAME}" ] && echo "IAM_EXT_USERNAME is not set" && exit 1 || echo "Target object ARN is set to '${IAM_EXT_USERNAME}'"
[ -z "${IAM_EKS_CLUSTER_ADMIN_ROLE}" ] && echo "IAM_EKS_CLUSTER_ADMIN_ROLE is not set" && exit 1 || echo "Cluster Admin IAM role name is set to '${IAM_EKS_CLUSTER_ADMIN_ROLE}'"
[ -z "${ACCOUNT_ID}" ] && echo "ACCOUNT_ID is not set" && exit 1 || echo "Account ID is set to '${ACCOUNT_ID}'"
[ -z "${CLUSTER_NEW_ADMIN_RBAC_NAME}" ] && echo "CLUSTER_NEW_ADMIN_RBAC_NAME is not set" && exit 1 || echo "Kubernetes RBAC entry name is set to '${CLUSTER_NEW_ADMIN_RBAC_NAME}'"

print_line "Modifying cluster configuration to grant access..."

accessConfig="$(aws eks describe-cluster --region $REGION --name $EKS_CLUSTER_NAME --query "cluster.accessConfig.authenticationMode" --no-cli-pager --output yaml)"
verify_status "Fetched cluster's current auth-mode config" "Failed to fetch cluster's current auth-mode config"

echo "$accessConfig" | grep -q "API_AND_CONFIG_MAP" && authConfigOK=true || authConfigOK=false

[ "$authConfigOK" = 'true' ] && echo "Current auth-mode config OK. Proceeding..."
if [ "$authConfigOK" = 'false' ]; then
  aws eks update-cluster-config --name $EKS_CLUSTER_NAME --access-config 'authenticationMode=API_AND_CONFIG_MAP' >/dev/null
  verify_status "Modified auth mode configuration" "Auth mode reconfiguration failed"

  echo "Waiting for the modification to take place..."

  spin &
  spinpid=$!
  while true; do
    sleep 10
    clusterStatus="$(aws eks describe-cluster --region $REGION --name $EKS_CLUSTER_NAME --query "cluster.status" --no-cli-pager)"
    echo "$clusterStatus" | grep -iq active && break
  done
  kill $spinpid

  accessConfig="$(aws eks describe-cluster --region $REGION --name $EKS_CLUSTER_NAME --query "cluster.accessConfig.authenticationMode" --no-cli-pager --output yaml)"
  verify_status "Fetched cluster's current auth-mode config" "Failed to fetch cluster's current auth-mode config"

  echo "$accessConfig" | grep -q "API_AND_CONFIG_MAP" && authConfigOK=true || authConfigOK=false

  [ "$authConfigOK" = 'true' ] && echo "Modified configuration successfully. Proceeding..."
  if [ "$authConfigOK" = 'false' ]; then
    echo "Failed to modify configuration."
    echo "Run 'aws eks update-cluster-config --name $EKS_CLUSTER_NAME --access-config authenticationMode=API_AND_CONFIG_MAP' to troubleshoot"
    echo "Exiting..." && exit 1
  fi
fi

print_line "Creating IAM role for the secondary ARN..."

cat >policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${ACCOUNT_ID}:user/${IAM_EXT_USERNAME}"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

existingRoles="$(aws iam list-roles --query 'Roles[].RoleName' --no-cli-pager --output yaml)"
echo "$existingRoles" | grep -Eq "^- $IAM_EKS_CLUSTER_ADMIN_ROLE$" && roleExists=true || roleExists=false

[ "$roleExists" = "true" ] && echo "Cluster role ($IAM_EKS_CLUSTER_ADMIN_ROLE) already exists. Skipping..."
if [ "$roleExists" = "false" ]; then
  aws iam create-role --role-name "$IAM_EKS_CLUSTER_ADMIN_ROLE" --assume-role-policy-document file://"policy.json" --no-cli-pager >/dev/null
  verify_status "Cluster Admin role created ($IAM_EKS_CLUSTER_ADMIN_ROLE)" "Cluster Admin role creation failed"
fi

print_line "Creating cluster access entries and cluster rolebindings..."

cat >policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "eks:DescribeCluster",
      "Resource": "arn:aws:eks:${REGION}:${ACCOUNT_ID}:cluster/${EKS_CLUSTER_NAME}"
    }
  ]
}
EOF

aws iam put-role-policy --policy-name "$IAM_EKS_CLUSTER_ADMIN_ROLE-policy" --role-name "$IAM_EKS_CLUSTER_ADMIN_ROLE" --policy-document file://"policy.json"
verify_status "Successfully attached inline policy to '$IAM_EKS_CLUSTER_ADMIN_ROLE'" "Failed to attach inline policy to '$IAM_EKS_CLUSTER_ADMIN_ROLE'"

sleep 2

aws eks create-access-entry --cluster-name $EKS_CLUSTER_NAME \
  --principal-arn "arn:aws:iam::${ACCOUNT_ID}:role/${IAM_EKS_CLUSTER_ADMIN_ROLE}" \
  --type STANDARD --username $CLUSTER_NEW_ADMIN_RBAC_NAME >/dev/null
verify_status "Successfully created access entry for role '$IAM_EKS_CLUSTER_ADMIN_ROLE'" "Failed to create access entry for role '$IAM_EKS_CLUSTER_ADMIN_ROLE'"

kubectl get clusterrolebindings -A | awk -F' ' '{print $1}' | grep -qE "^$CLUSTER_NEW_ADMIN_RBAC_NAME" && rbExists='true' || rbExists='false'
if [ "$rbExists" = "true" ]; then
  echo "A clusterrolebinding to user $CLUSTER_NEW_ADMIN_RBAC_NAME already exists. Please investigate. Exiting..."
  exit 1
fi

if [ "$rbExists" = "false" ]; then
  kubectl create clusterrolebinding remote-cluster-admin \
    --clusterrole=cluster-admin \
    --user=$CLUSTER_NEW_ADMIN_RBAC_NAME >/dev/null
fi
verify_status "Cluster rolebinding created for $IAM_EKS_CLUSTER_ADMIN_ROLE" "Cluster rolebinding creation for $IAM_EKS_CLUSTER_ADMIN_ROLE failed"

print_line "Setup instructions..."

echo "Paste the following lines as they are on the CLI of the user you want to grant administration rights for the kubernetes cluster."
echo "The user must be the same as the ARN specified in the variables. If the ARN is an assumed role. make sure to assume this role before executing the commands."
echo
sleep 2
./helpers/UT_printUserCommand.sh

rm -f policy.json
