#!/bin/bash

text='# =========== General Variables ================
export ACCOUNT_ID="XXXXXXXXXXXX"
export REGION="regionCode" # eg eu-central-1

# =========== Cluster Variables ================
export EKS_CLUSTER_NAME="MyCluster"
export EKS_KUBE_VERSION="1.XX"
export EKS_SUBNET_1="subnet-XXXXXXXXXX" # Need to be on different AZs
export EKS_SUBNET_2="subnet-XXXXXXXXXX" # Need to be on different AZs

# ===== These 2 are necessary only for cluster to rights to IAM users =====
export IAM_EXT_USERNAME="myUsername" # EXISTING user you want to give kubectl access / aws iam list-users --query Users[].UserName
export CLUSTER_NEW_ADMIN_RBAC_NAME="IAM-ClusterAdmin"   # Name of the new RBAC entry that will be created in the cluster

# =========== NodeGroup Variables ===========
# aws eks create-nodegroup help
export NODEGROUP_NAME="MyNodeGroup"
export NODEGROUP_SSH_KEY_NAME="MyKeyPair" # aws ec2 describe-key-pairs --query "KeyPairs[].{Name:KeyName}" --no-cli-pager
export NODEGROUP_AMI_TYPE="AL2023_x86_64_STANDARD"
export NODEGROUP_INSTANCE_SIZE="t3.medium"
export NODEGROUP_CAPACITY="ON_DEMAND" # SPOT / ON_DEMAND / CAPACITY_BLOCK
export NODEGROUP_MINSIZE="1"
export NODEGROUP_MAXSIZE="2"
export NODEGROUP_DESIREDSIZE="1"

# ============= No need to modify (optional) ===========
# Name of the new role that will be created for the IAM user
export IAM_EKS_CLUSTER_ADMIN_ROLE="${EKS_CLUSTER_NAME}-cluster-admin-role"
# Name of the new role that will be created for the cluster
export IAM_CLUSTER_ROLE="${EKS_CLUSTER_NAME}-cluster-role"
# Name of the new role that will be created for the EFS CSI drivers. Cluster service account will be annotated with it
export IAM_EFS_CSI_ROLE_NAME="${EKS_CLUSTER_NAME}-EFS_CSI_DriverRole"
# Name of the new role that will be created for the EBS CSI drivers. Cluster service account will be annotated with it
export IAM_EBS_CSI_ROLE_NAME="${EKS_CLUSTER_NAME}-EBS-CSI-Role"
# Name of the new role that will be created for the VPN CNI addon. Cluster service account will be annotated with it
export IAM_VPC_CNI_ROLE_NAME="${EKS_CLUSTER_NAME}-CNI-Role"
# Name of the new role that will be created for the worker nodes
export NODE_ROLE_NAME="${EKS_CLUSTER_NAME}-node-role"
# ARN of the new role that will be created for the worker nodes
export NODE_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${NODE_ROLE_NAME}"

# ================ Auto-generated ===========
'

echo "$text" > 00_variables.sh
