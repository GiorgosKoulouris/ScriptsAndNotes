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
[ -z "${ACCOUNT_ID}" ] && echo "ACCOUNT_ID is not set" && exit 1 || echo "Account ID is set to '${ACCOUNT_ID}'"
[ -z "${REGION}" ] && echo "REGION is not set" && exit 1 || echo "Region is set to '${REGION}'"

print_line "Checking for duplicate providers..."

OIDC_FULL="$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --no-cli-pager --query 'cluster.identity.oidc.issuer' --output text)"
verify_status "Fetched OIDC issuer URL" "Faield to fetch OIDC issuer URL"

OIDC_ID=$(echo "$OIDC_FULL" | awk -F'/' '{print $NF}')
syntaxedARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}"

grep -v "export OIDC_PROVIDER_ARN=" 00_variables.sh >vars.tmp && mv vars.tmp 00_variables.sh && echo "export OIDC_PROVIDER_ARN=\"$syntaxedARN\"" >>00_variables.sh
source 00_variables.sh

arnList=$(aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[].Arn' --no-cli-pager --output yaml)

echo "$arnList" | grep -q "$syntaxedARN" && oidcExists='true' || oidcExists='false'

if [ "$oidcExists" = 'true' ]; then
  echo "An OIDC provider for this cluster already exists. Skipping..."
  exit 0
else
  echo "No OIDC provider found for cluster $EKS_CLUSTER_NAME. Proceeding."
fi

print_line "Creating OIDC Provider..."

aws iam create-open-id-connect-provider --url "$OIDC_FULL" --client-id-list "sts.amazonaws.com" --no-cli-pager >/dev/null
verify_status "Created IAM OIDC Provider" "Failed to create IAM OIDC Provider"




