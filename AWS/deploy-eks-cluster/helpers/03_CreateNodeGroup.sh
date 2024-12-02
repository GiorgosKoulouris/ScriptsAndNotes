# ======== Create Node Group ==========

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
[ -z "${NODE_ROLE_NAME}" ] && echo "NODE_ROLE_NAME is not set" && exit 1 || echo "Role name for nodegroup nodes is set to '${NODE_ROLE_NAME}'"
[ -z "${NODE_ROLE_ARN}" ] && echo "NODE_ROLE_ARN is not set" && exit 1 || echo "Role ARN for nodegroup nodes is set to '${NODE_ROLE_ARN}'"
[ -z "${NODEGROUP_NAME}" ] && echo "NODEGROUP_NAME is not set" && exit 1 || echo "Nodegroup name is set to '${NODEGROUP_NAME}'"
[ -z "${EKS_SUBNET_1}" ] && echo "EKS_SUBNET_1 is not set" && exit 1 || echo "Subnet 1 ID is set to '${EKS_SUBNET_1}'"
[ -z "${EKS_SUBNET_2}" ] && echo "EKS_SUBNET_2 is not set" && exit 1 || echo "Subnet 2 ID is set to '${EKS_SUBNET_2}'"
[ -z "${NODEGROUP_MINSIZE}" ] && echo "NODEGROUP_MINSIZE is not set" && exit 1 || echo "Min size for nodegroup is set to '${NODEGROUP_MINSIZE}'"
[ -z "${NODEGROUP_MAXSIZE}" ] && echo "NODEGROUP_MAXSIZE is not set" && exit 1 || echo "Max size for nodegroup is set to '${NODEGROUP_MAXSIZE}'"
[ -z "${NODEGROUP_DESIREDSIZE}" ] && echo "NODEGROUP_DESIREDSIZE is not set" && exit 1 || echo "Desired size for nodegroup is set to '${NODEGROUP_DESIREDSIZE}'"
[ -z "${NODEGROUP_INSTANCE_SIZE}" ] && echo "NODEGROUP_INSTANCE_SIZE is not set" && exit 1 || echo "Instance type for nodegroup nodes is set to '${NODEGROUP_INSTANCE_SIZE}'"
[ -z "${NODEGROUP_CAPACITY}" ] && echo "NODEGROUP_CAPACITY is not set" && exit 1 || echo "Capacity for nodegroup is set to '${NODEGROUP_CAPACITY}'"
[ -z "${NODEGROUP_AMI_TYPE}" ] && echo "NODEGROUP_AMI_TYPE is not set" && exit 1 || echo "Ami Type for nodegroup is set to '${NODEGROUP_AMI_TYPE}'"
[ -z "${NODEGROUP_SSH_KEY_NAME}" ] && echo "NODEGROUP_SSH_KEY_NAME is not set" && exit 1 || echo "SSH KeyPair for nodegroup is set to '${NODEGROUP_SSH_KEY_NAME}'"

print_line "Creating necessary IAM roles and policies..."

cat >policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "ec2.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

existingRoles="$(aws iam list-roles --query 'Roles[].RoleName' --no-cli-pager --output yaml)"
echo "$existingRoles" | grep -Eq "^- $NODE_ROLE_NAME$" && roleExists=true || roleExists=false

[ "$roleExists" = "true" ] && echo "Node role ($NODE_ROLE_NAME) already exists. Skipping..."
if [ "$roleExists" = "false" ]; then
  aws iam create-role --role-name "$NODE_ROLE_NAME" --assume-role-policy-document file://"policy.json" --no-cli-pager >/dev/null
  verify_status "Node role created" "Failed to create Node role"
fi

rm -f policy.json

aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy --role-name "$NODE_ROLE_NAME" && \
  aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly --role-name "$NODE_ROLE_NAME"
verify_status "Attached policies to node role" "Failed to attach policies to node role"

print_line "Creating node group $NODEGROUP_NAME..."

existingNodegroups="$(aws eks list-nodegroups --cluster-name "$EKS_CLUSTER_NAME" --query 'nodegroups[]' --output yaml --no-cli-pager)"
echo "$existingNodegroups" | grep -Eq "^- $NODEGROUP_NAME$" && nodegroupExists=true || nodegroupExists=false

[ "$nodegroupExists" = "true" ] && echo "Nodegroup ($NODEGROUP_NAME) already exists. Skipping..."
if [ "$nodegroupExists" = "false" ]; then
  aws eks create-nodegroup \
    --nodegroup-name "$NODEGROUP_NAME" \
    --cluster-name "$EKS_CLUSTER_NAME" \
    --region "$REGION" \
    --subnets "$EKS_SUBNET_1" "$EKS_SUBNET_2" \
    --scaling-config minSize=${NODEGROUP_MINSIZE},maxSize=${NODEGROUP_MAXSIZE},desiredSize=${NODEGROUP_DESIREDSIZE} \
    --instance-types "$NODEGROUP_INSTANCE_SIZE" \
    --capacity-type "$NODEGROUP_CAPACITY" \
    --ami-type "$NODEGROUP_AMI_TYPE" \
    --remote-access "ec2SshKey=${NODEGROUP_SSH_KEY_NAME}" \
    --node-role "$NODE_ROLE_ARN" \
    --no-cli-pager >/dev/null
  verify_status "Created nodegroup" "Failed to create nodegroup"
fi

echo "Waiting nodegroup's readiness..."

spin &
spinpid=$!
while true; do
  nodegroupStatus=$(aws eks describe-nodegroup --cluster-name "$EKS_CLUSTER_NAME" --nodegroup-name $NODEGROUP_NAME --query nodegroup.status --output text --no-cli-pager)

  echo "$nodegroupStatus" | grep -iq active && tempStatus='active'
  echo "$nodegroupStatus" | grep -iq failed && tempStatus='failed'

  if [ "$tempStatus" = 'active' ]; then
    kill $spinpid
    echo
    echo "Nodegroup is ready..."
    break
  fi

  if [ "$tempStatus" = 'failed' ]; then
    kill $spinpid
    echo
    echo "Nodegroup $NODEGROUP_NAME creation failed."
    sleep 2
    aws eks describe-nodegroup --cluster-name "$EKS_CLUSTER_NAME" --nodegroup-name $NODEGROUP_NAME --query nodegroup.health --output json --no-cli-pager
    break
  fi

  sleep 10
done
