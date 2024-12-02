# Modify variables before sourcing
source 00_variables.sh

# Cluster Role
aws iam detach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy --role-name "$IAM_CLUSTER_ROLE"
aws iam delete-role --role-name "$IAM_CLUSTER_ROLE"

# IAM cluster Admin role
aws iam delete-role-policy --policy-name "$IAM_EKS_CLUSTER_ADMIN_ROLE-policy" --role-name "$IAM_EKS_CLUSTER_ADMIN_ROLE"
aws iam delete-role --role-name "$IAM_EKS_CLUSTER_ADMIN_ROLE"

# IAM Role for CNI
aws iam detach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy --role-name "$IAM_VPC_CNI_ROLE_NAME"
aws iam delete-role --role-name "$IAM_VPC_CNI_ROLE_NAME"

# IAM Role for CSI Driver (EFS mounts)
aws iam delete-role-policy --role-name "$IAM_EFS_CSI_ROLE_NAME" --policy-name "${IAM_EFS_CSI_ROLE_NAME}_policy"
aws iam delete-role --role-name "$IAM_EFS_CSI_ROLE_NAME"

# IAM Role for CSI Driver (EBS mounts)
aws iam detach-role-policy --role-name "$IAM_EBS_CSI_ROLE_NAME" --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
aws iam delete-role --role-name "$IAM_EBS_CSI_ROLE_NAME"

# Delete EFS and/or mountPoint
aws efs delete-mount-target --mount-target-id $EFS_MOUNT_ID_1
aws efs delete-mount-target --mount-target-id $EFS_MOUNT_ID_2
aws efs describe-file-systems --file-system-id $EFS_ID --query 'FileSystems[0].NumberOfMountTargets' --output text --no-cli-pager # When 0, proceed with EFS deletion
aws efs delete-file-system --file-system-id $EFS_ID --no-cli-pager
aws efs describe-file-systems --file-system-id $EFS_ID --query 'FileSystems[0].LifeCycleState' --output text --no-cli-pager # Verify

# # Delete IAM Role for Pods
# IAM_POD_ROLE_NAME="${EKS_CLUSTER_NAME}_PodRole"
# IAM_POD_POLICY_NAME="${IAM_POD_ROLE_NAME}_Policy"
# aws iam delete-role-policy --role-name "$IAM_POD_ROLE_NAME" --policy-name "$IAM_POD_POLICY_NAME"
# aws iam delete-role --role-name "$IAM_POD_ROLE_NAME"

# Node group
aws eks delete-nodegroup --cluster-name "$EKS_CLUSTER_NAME" --nodegroup-name "$NODEGROUP_NAME" --query "nodegroup.status" --no-cli-pager
aws eks describe-nodegroup --cluster-name "$EKS_CLUSTER_NAME" --nodegroup-name "$NODEGROUP_NAME" --query "nodegroup.status" --no-cli-pager
aws eks describe-nodegroup --cluster-name "$EKS_CLUSTER_NAME" --nodegroup-name "$NODEGROUP_NAME" --query "nodegroup.health" --no-cli-pager # If deletion fails

# DELETE CLuster
aws eks delete-cluster --name $EKS_CLUSTER_NAME --query 'cluster.status' --output text --no-cli-pager
aws eks describe-cluster --name $EKS_CLUSTER_NAME --query "cluster.status" --output text --no-cli-pager
aws eks describe-cluster --name $EKS_CLUSTER_NAME --query "cluster.health" --output text --no-cli-pager # If deletion fails

# Node Role, needs profile to have been removed by nodegroup's instance profile 1st. May take some mins after you delete the nodegroup
aws iam detach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy --role-name "$NODE_ROLE_NAME"
aws iam detach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly --role-name "$NODE_ROLE_NAME"
aws iam delete-role --role-name "$NODE_ROLE_NAME"

# Extras
aws ec2 delete-security-group --group-id "$EFS_SG_ID"
aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN"
