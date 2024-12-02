# https://docs.aws.amazon.com/eks/latest/userguide/associate-service-account-role.html

source ../00_variables.sh

SERVICE_ACCOUNT_NAME="test-pod-sa"
NAMESPACE_SCOPE="default"

OIDC_PROVIDER=$(aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region $REGION --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")

IAM_POD_ROLE_NAME="${EKS_CLUSTER_NAME}_Test_PodRole"
IAM_POD_POLICY_NAME="${IAM_POD_ROLE_NAME}_Test_PodRole_Policy"

SA_YAML_FILE=testSA.yaml
TEST_TRUST_REL_JSON=testTrustPolicy.json
TEST_MAINPOL_YAML=testMainPolicy.json

# Create service account
cat >"$SA_YAML_FILE" <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SERVICE_ACCOUNT_NAME}
  namespace: ${NAMESPACE_SCOPE}
EOF

cat >"$TEST_TRUST_REL_JSON" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${NAMESPACE_SCOPE}:${SERVICE_ACCOUNT_NAME}"
        }
      }
    }
  ]
}
EOF

# Example policy
cat >"$TEST_MAINPOL_YAML" <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::*"
        }
    ]
}
EOF

aws iam create-role --role-name "$IAM_POD_ROLE_NAME" --assume-role-policy-document file://${TEST_TRUST_REL_JSON} --description "Test Role for Podss" >/dev/null
aws iam put-role-policy --policy-name "$IAM_POD_POLICY_NAME" --role-name "$IAM_POD_ROLE_NAME" --policy-document file://"$TEST_MAINPOL_YAML" >/dev/null

kubectl apply -f "$SA_YAML_FILE"
kubectl annotate serviceaccount \
  -n $NAMESPACE_SCOPE $SERVICE_ACCOUNT_NAME \
  eks.amazonaws.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/${IAM_POD_ROLE_NAME}

# ============ CLEANUP ============
kubectl delete serviceaccount \
  -n $NAMESPACE_SCOPE $SERVICE_ACCOUNT_NAME

aws iam delete-role-policy --policy-name "$IAM_POD_POLICY_NAME" --role-name "$IAM_POD_ROLE_NAME"
aws iam delete-role --role-name "$IAM_POD_ROLE_NAME"
rm -f "$TEST_TRUST_REL_JSON"
rm -f "$SA_YAML_FILE"
rm -f "$TEST_TRUST_REL_JSON"
rm -f "$TEST_MAINPOL_YAML"
