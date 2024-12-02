<h1>Create and configure an EKS cluster</h1>

<h2>Overview</h2>

By running this script you can provision and configure an EKS cluster. Based on the option will provision specific object or perform specific actions.

<h2>Prerequisites</h2>

Because the script creates objects in the EC2, VPC, EKS and IAM realms, your user will need to have most of the related read/write/list permissions on these services.

<b>Note</b>: It is best practice to execute the cluster provioning step from cloudshell or with a user who has console access. This way you will make sure that you will have full permissions on the cluster from AWS console without further modifications. Later, you can provide administrative access to the cluster to other IAM entities.

<b>Note</b>: The script does not provision the underlying network for the cluster, so create a VPC and the related network objects that are compatible with EKS cluster hosting.

<h2>Info</h2>

Clone the repository, navigate to the folder containing the script and execute the following to get an overview of the possilble options:

```bash
git clone https://github.com/GiorgosKoulouris/ScriptsAndNotes.git
cd ScriptsAndNotes/AWS/deploy-eks-cluster
./00_clusterActions.sh --help
```

<h2>Variable file</h2>

All of the related variables (names, IDs etc) are stored in the *00_variables.sh* file, which is sourced by the main and helper scripts. This file is auto-filled with any extra
information gets generated later on, in order to stay updated.

Keep in mind that if you delete or modify the file, the script will not be able to run properly. For multiple deployments, it is best practice to have multiple variable files as well.
The configuration you are going to be actively deploying needs to be related to a file named *00_variables.sh*.

You can generate an initialized var file and then modify it accordingly. Note that this action overwrites the *00_variables.sh* file. Execute:

```bash
# Generate the file
./00_clusterActions.sh --init-vars

# Edit the file
vi 00_variables.sh

# Good practice to source it after modifying in order to execute adhoc commands using the vars
source 00_variables.sh
```

Editing the file by filling every variable once would be enough. You don't need to edit the file between script executions, unless you want to deploy another cluster.

<h2>Usage</h2>

After modifying the var file, you can start deploying.

In general, you can execute the same script multiple times without breaking anything, as there are evaluation steps before each action. So if a script fails, try to execute it
once or twice more. Anything that has beed already provisioned will be skipped.

<h3>Create the Cluster</h3>

This is the initial step. Execute the following to provision an EKS cluster.

These environment variables must be set before executing, or the script will return an error:
- ACCOUNT_ID
- REGION
- EKS_CLUSTER_NAME
- EKS_KUBE_VERSION
- IAM_CLUSTER_ROLE
- EKS_SUBNET_1
- EKS_SUBNET_2

```bash
# Create cluster
./00_clusterActions.sh --create-cluster
```

<h3>Give cluster administrative access to an IAM user</h3>

Execute this if you want to give another user of the account administrative access to the cluster.
Note that this script gives cluster-wide admin rights to the specified user.

These environment variables must be set before executing, or the script will return an error:
- EKS_CLUSTER_NAME
- REGION
- IAM_EXT_USERNAME
- IAM_EKS_CLUSTER_ADMIN_ROLE
- ACCOUNT_ID
- CLUSTER_NEW_ADMIN_RBAC_NAME

```bash
# Grant admin access to user
./00_clusterActions.sh --grantAdmin-to-IAM
```

<h3>Create an OpenID Identity Provider for the cluster</h3>

Execute this in order to create a new OIDC identity provider in your account's IAM section in order to let the ServiceAccounts of the cluster assume IAM roles.

You will need an active cluster for this.

These environment variables must be set before executing, or the script will return an error:
- EKS_CLUSTER_NAME
- REGION
- ACCOUNT_ID

```bash
# Create OIDC provider
./00_clusterActions.sh --create-OIDC-provider
```

<h3>Install VPC CNI Addon</h3>

Execute this in order to install VPC CNI to enable cluster networking using the underlying VPC as a medium. The OIDC provider is a prerequisite for this.

These environment variables must be set before executing, or the script will return an error:
- EKS_CLUSTER_NAME
- REGION
- ACCOUNT_ID
- IAM_VPC_CNI_ROLE_NAME

```bash
# Install VPC CNI
./00_clusterActions.sh --install-VPC-CNI
```

<h3>Create node group</h3>

Execute this in order to configure and deploy a node group for this cluster. Having the cluster networking configured is a prerequisite, so either configure it using VPN CNI
or with any plugin of your choice.

These environment variables must be set before executing, or the script will return an error:
 - ACCOUNT_ID
 - REGION
 - EKS_CLUSTER_NAME
 - NODE_ROLE_NAME
 - NODE_ROLE_ARN
 - NODEGROUP_NAME
 - EKS_SUBNET_1
 - EKS_SUBNET_2
 - NODEGROUP_MINSIZE
 - NODEGROUP_MAXSIZE
 - NODEGROUP_DESIREDSIZE
 - NODEGROUP_INSTANCE_SIZE
 - NODEGROUP_CAPACITY
 - NODEGROUP_AMI_TYPE
 - NODEGROUP_SSH_KEY_NAME

```bash
# Create nodegroup
./00_clusterActions.sh --create-nodegroup
```

<h3>Install EBS addon</h3>

Execute this in order to install the EBS addon which is used to mount EBS volumes to pods. The OIDC provider is a prerequisite for this.

These environment variables must be set before executing, or the script will return an error:
 - ACCOUNT_ID
 - REGION
 - EKS_CLUSTER_NAME
 - IAM_EBS_CSI_ROLE_NAME

```bash
# Install EBS addon
./00_clusterActions.sh --install-EBS-addon
```

<h3>Install EFS addon</h3>

Execute this in order to install the EFS addon which is used to mount EFS filesystems to pods. The OIDC provider is a prerequisite for this.

These environment variables must be set before executing, or the script will return an error:
 - ACCOUNT_ID
 - REGION
 - EKS_CLUSTER_NAME
 - IAM_EBS_CSI_ROLE_NAME

```bash
# Install EFS addon
./00_clusterActions.sh --install-EFS-addon
```

<h3>Create an EFS for the cluster</h3>

This is not entirely EKS related. Creates an EFS with 2 mounts, one in each Subnet the cluster is. Also creates the appropriate security groups and rules.

These environment variables must be set before executing, or the script will return an error:
 - ACCOUNT_ID
 - REGION
 - EKS_CLUSTER_NAME
 - IAM_EBS_CSI_ROLE_NAME
 - EKS_SUBNET_1
 - EKS_SUBNET_2

```bash
# Create EFS
./00_clusterActions.sh --create-dedicated-EFS
```

<h2>Cleanup</h2>

If you want to delete anything that was created by running these scripts, review the commands in the file *ZZ_Cleanup.h* and execute the commands one by one.
Make sure you have first sourced the variables first by executing:

```bash
source 00_variables.sh
```

Do not execute the file, just copy-paste the commands.