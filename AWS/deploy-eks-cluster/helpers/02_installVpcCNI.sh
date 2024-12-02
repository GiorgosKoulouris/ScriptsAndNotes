#!/bin/bash

# https://docs.aws.amazon.com/eks/latest/userguide/cni-iam-role.html

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

[ -z "${ACCOUNT_ID}" ] && echo "ACCOUNT_ID is not set" && exit 1 || echo "Account ID is set to '${ACCOUNT_ID}'"
[ -z "${REGION}" ] && echo "REGION is not set" && exit 1 || echo "Region is set to '${REGION}'"
[ -z "${EKS_CLUSTER_NAME}" ] && echo "EKS_CLUSTER_NAME is not set" && exit 1 || echo "Cluster Name is set to '${EKS_CLUSTER_NAME}'"
[ -z "${IAM_VPC_CNI_ROLE_NAME}" ] && echo "IAM_VPC_CNI_ROLE_NAME is not set" && exit 1 || echo "Role name for VPC CNI is set to '${IAM_VPC_CNI_ROLE_NAME}'"

print_line "This script is compatible with ipv4 only clusters. Verifying compatibility..."

ipVersion=$(aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --query cluster.kubernetesNetworkConfig.ipFamily --output text --no-cli-pager)
if [ "$ipVersion" = 'ipv4' ]; then
  echo "$EKS_CLUSTER_NAME cluster networking is compatible. Proceeding."
else
  echo "$EKS_CLUSTER_NAME cluster networking is not compatible. Exiting..."
  exit 1
fi

print_line "Checking compatibility of latest version with cluster's version..."

compatibleVersions=$(aws eks describe-addon-versions \
  --addon-name vpc-cni \
  --query "addons[0].addonVersions[0].compatibilities[].clusterVersion" \
  --no-cli-pager \
  --output yaml)
verify_status "Fetched compatible kubernetes versions for the latest addon version" "Failed to fetch the compatible kubernetes versions"

clusterVersion=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --no-cli-pager --query cluster.version | tr -d '"')
verify_status "Fetched kubernetes version of cluster $EKS_CLUSTER_NAME" "Failed to fetch kubernetes version of cluster $EKS_CLUSTER_NAME"

echo "$compatibleVersions" | grep -q "$clusterVersion" && isCompatible='true' || isCompatible='false'

[ "$isCompatible" = 'true' ] && echo "Latest version of VPC CNI is compatible with cluster $EKS_CLUSTER_NAME. Proceeding."
if [ "$isCompatible" = 'false' ]; then
  echo "Latest version of VPC CNI is not compatible with cluster $EKS_CLUSTER_NAME. Exiting..."
  exit 1
fi

print_line "Creating necessary IAM roles and policies..."

OIDC_FULL=$(aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --query "cluster.identity.oidc.issuer" --output text)
OIDC_ID=$(echo "$OIDC_FULL" | awk -F'/' '{print $NF}')

cat >trust-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}:aud": "sts.amazonaws.com",
                    "oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}:sub": "system:serviceaccount:kube-system:aws-node"
                }
            }
        }
    ]
}
EOF

existingRoles="$(aws iam list-roles --query 'Roles[].RoleName' --no-cli-pager --output yaml)"
echo "$existingRoles" | grep -Eq "^- $IAM_VPC_CNI_ROLE_NAME$" && roleExists=true || roleExists=false

[ "$roleExists" = "true" ] && echo "CNI role ($IAM_VPC_CNI_ROLE_NAME) already exists. Skipping..."
if [ "$roleExists" = "false" ]; then
  aws iam create-role --role-name "$IAM_VPC_CNI_ROLE_NAME" --assume-role-policy-document file://"trust-policy.json" --no-cli-pager >/dev/null
  verify_status "CNI role created" "Failed to create CNI role"
fi

aws iam attach-role-policy --role-name "$IAM_VPC_CNI_ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
verify_status "Attached CNI role policies" "Could not attach policies to CNI role"

[ -f trust-policy.json ] && rm -f trust-policy.json

print_line "Verifying no version of the addon is installed..."

installedAddons=$(aws eks list-addons --cluster-name "$EKS_CLUSTER_NAME" --query addons --output yaml --no-cli-pager)
verify_status "Fetched installed addons" "Failed to fetch installed addons"

echo "$installedAddons" | grep -iq vpc-cni && isPresent='true' || isPresent='false'
[ "$isPresent" = 'false' ] && echo "Did not find any installed addon versions for VPC CNI. Proceeding."
if [ "$isPresent" = 'true' ]; then
  echo "Addon already installed. Exiting..."
  exit 0
fi

print_line "Installing addon.."

aws eks create-addon --cluster-name "$EKS_CLUSTER_NAME" \
  --addon-name vpc-cni \
  --service-account-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${IAM_VPC_CNI_ROLE_NAME}" \
  --no-cli-pager >/dev/null
verify_status "Created addon" "Failed to create addon"

echo "Waiting addon's readiness..."

spin &
spinpid=$!
while true; do
  addonStatus=$(aws eks describe-addon --cluster-name "$EKS_CLUSTER_NAME" --addon-name vpc-cni --query addon.status)

  echo "$addonStatus" | grep -iq active && tempStatus='active'
  echo "$addonStatus" | grep -iq failed && tempStatus='failed'

  if [ "$tempStatus" = 'active' ]; then
    kill $spinpid
    echo
    echo "Addon is ready..."
    break
  fi

  if [ "$tempStatus" = 'failed' ]; then
    kill $spinpid
    echo
    echo "Addon addition to cluster $EKS_CLUSTER_NAME failed."
    aws eks describe-addon --cluster-name "$EKS_CLUSTER_NAME" --addon-name vpc-cni --query addon.health --no-cli-pager
    break
  fi

  sleep 10
done



