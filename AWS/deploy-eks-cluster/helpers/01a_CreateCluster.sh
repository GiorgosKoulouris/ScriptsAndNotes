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

[ -z "${ACCOUNT_ID}" ] && echo "ACCOUNT_ID is not set" && exit 1 || echo "Account ID is set to '${ACCOUNT_ID}'"
[ -z "${REGION}" ] && echo "REGION is not set" && exit 1 || echo "Region is set to '${REGION}'"
[ -z "${EKS_CLUSTER_NAME}" ] && echo "EKS_CLUSTER_NAME is not set" && exit 1 || echo "Cluster Name is set to '${EKS_CLUSTER_NAME}'"
[ -z "${EKS_KUBE_VERSION}" ] && echo "EKS_KUBE_VERSION is not set" && exit 1 || echo "Kubernetes version is set to '${EKS_KUBE_VERSION}'"
[ -z "${IAM_CLUSTER_ROLE}" ] && echo "IAM_CLUSTER_ROLE is not set" && exit 1 || echo "Cluster Role is set to '${IAM_CLUSTER_ROLE}'"
[ -z "${EKS_SUBNET_1}" ] && echo "EKS_SUBNET_1 is not set" && exit 1 || echo "Subnet 1 ID is set to '${EKS_SUBNET_1}'"
[ -z "${EKS_SUBNET_2}" ] && echo "EKS_SUBNET_2 is not set" && exit 1 || echo "Subnet 2 ID is set to '${EKS_SUBNET_2}'"

print_line "Creating cluster and necessary objects.."

cat >policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

existingRoles="$(aws iam list-roles --query 'Roles[].RoleName' --no-cli-pager --output yaml)"
echo "$existingRoles" | grep -Eq "^- $IAM_CLUSTER_ROLE$" && roleExists=true || roleExists=false

[ "$roleExists" = "true" ] && echo "Cluster role ($IAM_CLUSTER_ROLE) already exists. Skipping..."
if [ "$roleExists" = "false" ]; then
  aws iam create-role --role-name "$IAM_CLUSTER_ROLE" --assume-role-policy-document file://"policy.json" --no-cli-pager >/dev/null
  verify_status "Cluster role created" "Cluster role creation failed"
fi

rm -f policy.json

aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy --role-name "$IAM_CLUSTER_ROLE" --no-cli-pager
verify_status "Attached cluster role policies" "Could not attach policies to cluster role"

existingClusters="$(aws eks list-clusters --query 'clusters[]' --output yaml --no-cli-pager)"
echo "$existingClusters" | grep -Eq "^- $EKS_CLUSTER_NAME$" && clusterExists=true || clusterExists=false

[ "$clusterExists" = "true" ] && echo "Cluster ($EKS_CLUSTER_NAME) already exists. Skipping..."
if [ "$clusterExists" = "false" ]; then
  aws eks create-cluster --region $REGION --name $EKS_CLUSTER_NAME \
    --kubernetes-version $EKS_KUBE_VERSION \
    --role-arn arn:aws:iam::${ACCOUNT_ID}:role/${IAM_CLUSTER_ROLE} \
    --resources-vpc-config subnetIds=${EKS_SUBNET_1},${EKS_SUBNET_2} \
    --no-cli-pager >/dev/null

  verify_status "Cluster created" "Cluster creation failed"
fi

print_line "Waiting for the cluster's readiness..."

spin &
spinpid=$!
while true; do
  clusterStatus="$(aws eks describe-cluster --region $REGION --name $EKS_CLUSTER_NAME --query "cluster.status" --no-cli-pager)"

  echo "$clusterStatus" | grep -iq active && tempStatus='active'
  echo "$clusterStatus" | grep -iq failed && tempStatus='failed'

  if [ "$tempStatus" = 'active' ]; then
    kill $spinpid
    echo
    echo "Cluster is ready, printing info..."
    sleep 2
    aws eks describe-cluster --region $REGION --name $EKS_CLUSTER_NAME --output json --no-cli-pager
    break
  fi

  if [ "$tempStatus" = 'failed' ]; then
    kill $spinpid
    echo
    echo "Cluster build failed, printing info..."
    sleep 2
    aws eks describe-cluster --region $REGION --name $EKS_CLUSTER_NAME --query "cluster.health" --output json --no-cli-pager
    break
  fi

  sleep 10
done

print_line "Fetching kubernetes configuration..."

while true; do
  read -rp "Populate cluster config on your home folder? This will create a .bak of your ~/.kube/config file and replace the original with the new one. (y\n): " yn
  case "$yn" in
  [Yy]*)
    [ -f '~/.kube/config' ] && mv ~/.kube/config ~/.kube/config.bak
    aws eks update-kubeconfig --region $REGION --name $EKS_CLUSTER_NAME
    break
    ;;
  [Nn]*)
    echo
    echo "You will not be able to administer the cluster until you update your config. To update run:"
    echo "    [ -f '~/.kube/config' ] && mv ~/.kube/config ~/.kube/config.bak"
    echo "    aws eks update-kubeconfig --region $REGION --name $EKS_CLUSTER_NAME"
    echo
    break
    ;;
  *)
    echo "Please answer y or n"
    ;;
  esac
done
