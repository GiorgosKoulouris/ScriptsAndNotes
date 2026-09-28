#!/bin/bash

# https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/docs/efs-create-filesystem.md

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
[ -z "${EKS_SUBNET_1}" ] && echo "EKS_SUBNET_1 is not set" && exit 1 || echo "Subnet 1 ID is set to '${EKS_SUBNET_1}'"
[ -z "${EKS_SUBNET_2}" ] && echo "EKS_SUBNET_2 is not set" && exit 1 || echo "Subnet 2 ID is set to '${EKS_SUBNET_2}'"

print_line "Getting cluster's network info.."

VPC_ID=$(aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --query "cluster.resourcesVpcConfig.vpcId" --output text)
verify_status "Fetched VPC for cluster $EKS_CLUSTER_NAME" "Failed to fetch VPC for cluster $EKS_CLUSTER_NAME"

CIDR_RANGE_1=$(aws ec2 describe-subnets --subnet-ids $EKS_SUBNET_1 --query 'Subnets[0].CidrBlock' --no-cli-pager --output text)
verify_status "Fetched CIDR of subnet 1" "Failed to fetch CIDR of subnet 1"

CIDR_RANGE_2=$(aws ec2 describe-subnets --subnet-ids $EKS_SUBNET_2 --query 'Subnets[0].CidrBlock' --no-cli-pager --output text)
verify_status "Fetched CIDR of subnet 2" "Failed to fetch CIDR of subnet 2"

print_line "Creating dedicated security group..."

EFS_SG_NAME="$EKS_CLUSTER_NAME-EFS-SG"

sgNameList=$(aws ec2 get-security-groups-for-vpc --vpc-id $VPC_ID --query 'SecurityGroupForVpcs[].GroupName' --no-cli-pager --output yaml)
verify_status "Fetched security groups for VPC $VPC_ID" "Failed to fetch security groups for VPC $VPC_ID"

echo "$sgNameList" | grep -q "$EFS_SG_NAME" && sgExists='true' || sgExists='false'

if [ "$sgExists" = 'true' ]; then
  echo "A security group named $EFS_SG_NAME already exists. Exiting..."
  exit 1
fi

EFS_SG_ID=$(aws ec2 create-security-group --group-name $EFS_SG_NAME --description "$EKS_CLUSTER_NAME SG for EFS" --vpc-id $VPC_ID --output text)
verify_status "Created security group $EFS_SG_NAME" "Failed to create security group $EFS_SG_NAME"
grep -v "export EFS_SG_ID=" 00_variables.sh >vars.tmp && mv vars.tmp 00_variables.sh && echo "export EFS_SG_ID=\"$EFS_SG_ID\"" >>00_variables.sh

aws ec2 authorize-security-group-ingress --group-id $EFS_SG_ID --protocol tcp --port 2049 --cidr $CIDR_RANGE_1 --no-cli-pager >/dev/null
verify_status "Created rule for Subnet 1" "Failed to create rule for Subnet 1"

aws ec2 authorize-security-group-ingress --group-id $EFS_SG_ID --protocol tcp --port 2049 --cidr $CIDR_RANGE_2 --no-cli-pager >/dev/null
verify_status "Created rule for Subnet 2" "Failed to create rule for Subnet 2"

print_line "Creating EFS..."

EFS_ID=$(aws efs create-file-system \
  --region "$REGION" \
  --performance-mode generalPurpose \
  --encrypted \
  --throughput-mode 'elastic' \
  --no-backup \
  --query 'FileSystemId' \
  --output text)
verify_status "Created EFS $EFS_ID" "Failed to create EFS"
grep -v "export EFS_ID=" 00_variables.sh >vars.tmp && mv vars.tmp 00_variables.sh && echo "export EFS_ID=\"$EFS_ID\"" >>00_variables.sh

echo "Waiting for filesystem to be available..."

spin &
spinpid=$!
while true; do
  fsStatus="$(aws efs describe-file-systems --file-system-id $EFS_ID --query "FileSystems[0].LifeCycleState" --no-cli-pager --output text)"

  echo "$fsStatus" | grep -iq available && tempStatus='available'
  echo "$fsStatus" | grep -iq failed && tempStatus='failed'

  if [ "$tempStatus" = 'available' ]; then
    kill $spinpid
    echo
    echo "Filesystem is ready, proceeding..."
    break
  fi

  if [ "$tempStatus" = 'failed' ]; then
    kill $spinpid
    echo
    echo "Filesystem creation failed, printing info..."
    sleep 2
    aws eks describe-cluster --region $REGION --name $EKS_CLUSTER_NAME --query "cluster.health" --output json --no-cli-pager
    break
  fi

  sleep 5
done

EFS_MOUNT_ID_1=$(aws efs create-mount-target \
  --file-system-id $EFS_ID \
  --subnet-id "$EKS_SUBNET_1" \
  --security-groups $EFS_SG_ID \
  --query 'MountTargetId' \
  --output text)
verify_status "Created mount point for subnet 1" "Failed to create mount point for subnet 1"
grep -v "export EFS_MOUNT_ID_1=" 00_variables.sh >vars.tmp && mv vars.tmp 00_variables.sh && echo "export EFS_MOUNT_ID_1=\"$EFS_MOUNT_ID_1\"" >>00_variables.sh

EFS_MOUNT_ID_2=$(aws efs create-mount-target \
  --file-system-id $EFS_ID \
  --subnet-id "$EKS_SUBNET_2" \
  --security-groups $EFS_SG_ID \
  --query 'MountTargetId' \
  --output text)
verify_status "Created mount point for subnet 2" "Failed to create mount point for subnet 2"
grep -v "export EFS_MOUNT_ID_2=" 00_variables.sh >vars.tmp && mv vars.tmp 00_variables.sh && echo "export EFS_MOUNT_ID_2=\"$EFS_MOUNT_ID_2\"" >>00_variables.sh

echo "Waiting for mounts to be available..."

spin &
spinpid=$!
while true; do
  mountStatus1="$(aws efs describe-mount-targets --mount-target-id $EFS_MOUNT_ID_1 --query "MountTargets[0].LifeCycleState" --no-cli-pager --output text)"
  mountStatus2="$(aws efs describe-mount-targets --mount-target-id $EFS_MOUNT_ID_2 --query "MountTargets[0].LifeCycleState" --no-cli-pager --output text)"

  tempStatus='null'

  if ([ "$mountStatus1" = 'available' ] && [ "$mountStatus2" = 'available' ]); then
    tempStatus='available'
  fi

  tmp="${mountStatus1}/${mountStatus2}"
  echo "$tmp" | grep -iq failed && tempStatus='failed'

  if [ "$tempStatus" = 'available' ]; then
    kill $spinpid
    echo
    echo "Filesystem mounts are ready, proceeding..."
    break
  fi

  if [ "$tempStatus" = 'failed' ]; then
    kill $spinpid
    echo
    echo "Filesystem mount creation failed. Exiting..."
    exit 1
  fi

  sleep 5

done

source ./00_variables.sh
