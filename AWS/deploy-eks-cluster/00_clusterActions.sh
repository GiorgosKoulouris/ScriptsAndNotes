#!/bin/bash

source 00_variables.sh

print_line() {
    printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' .
}

usage() {
    echo
    echo "Usage:"
    echo "    $0 --init-vars                Only creates a template file for the variables. Edit the file afterwards."
    echo "    $0 --create-cluster           Creates EKS cluster."
    echo "    $0 --grantAdmin-to-IAM        Grants cluster administrative rights to an IAM entity."
    echo "    $0 --create-OIDC-provider     Create an OIDC provider to allow cluster to authenticate via IAM."
    echo "    $0 --install-VPC-CNI          Install VPC CNI to the cluster."
    echo "    $0 --create-nodegroup         Create node group."
    echo "    $0 --install-EBS-addon        Install the EBS addon to the cluster."
    echo "    $0 --install-EFS-addon        Install the EFS addon to the cluster."
    echo "    $0 --create-dedicated-EFS     Create EFS to use with the cluster."
    echo "    $0 --help                     Display this help message."
    echo "    $0 -h                         Display this help message."
    echo
}

check_args() {
    if [ $# -ne 1 ]; then
        echo "Invalid argument count."
        usage
        exit 1
    fi

    case "$1" in
    "--help")
        usage && exit 0
        ;;
    "-h")
        usage && exit 0
        ;;
    "--init-vars")
        init_variables
        ;;
    "--create-cluster")
        create_cluster
        ;;
    "--grantAdmin-to-IAM")
        grantAdminToIAM
        ;;
    "--create-OIDC-provider")
        create_oidc_provider
        ;;
    "--install-VPC-CNI")
        install_vpc_cni
        ;;
    "--create-nodegroup")
        create_nodegroup
        ;;
    "--install-EBS-addon")
        install_ebs_csi
        ;;
    "--install-EFS-addon")
        install_efs_csi
        ;;
    "--create-dedicated-EFS")
        create_dedicated_efs
        ;;
    *)
        echo "Invalid arguement"
        usage && exit 1
        ;;
    esac
}

init_variables() {
    echo
    print_line
    echo "Initializing variables..."
    echo

    read -rp "This will overwrite 00_variables.sh file. Proceed? " yn
    case $yn in
    [Yy]*)
        ./helpers/UT_initVariables.sh
        echo "Variables file (00_variables.sh) initialized"
        ;;
    *)
        echo "Exiting..."
        exit 0
        ;;
    esac
}

create_cluster() {
    echo
    print_line
    echo "Creating cluster..."
    echo

    ./helpers/01a_CreateCluster.sh
}

grantAdminToIAM() {
    echo
    print_line
    echo "Granting cluster administration rights to the cluster..."
    echo

    ./helpers/01b_GrantAccessToIAM.sh
}

create_oidc_provider() {
    echo
    print_line
    echo "Creating OIDC provider..."
    echo

    ./helpers/01c_CreateOICDProvider.sh
}

install_vpc_cni() {
    echo
    print_line
    echo "Installing VPC CNI..."
    echo

    ./helpers/02_installVpcCNI.sh
}

create_nodegroup() {
    echo
    print_line
    echo "Creating node group..."
    echo

    ./helpers/03_CreateNodeGroup.sh
}

install_ebs_csi() {
    echo
    print_line
    echo "Installing EBS addon..."
    echo

    ./helpers/04_InstallCsiEBS.sh
}

install_efs_csi() {
    echo
    print_line
    echo "Installing EFS addon..."
    echo

    ./helpers/04_InstallCsiEFS.sh
}

create_dedicated_efs() {
    echo
    print_line
    echo "Creating EFS..."
    echo 

    ./helpers/05_CreateDedicatedEFS.sh
}

check_args $@
