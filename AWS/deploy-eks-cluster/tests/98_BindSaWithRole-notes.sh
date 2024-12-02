# https://docs.aws.amazon.com/eks/latest/userguide/associate-service-account-role.html

source ../00_variables.sh

SERVICE_ACCOUNT_NAME="test-pod-sa"
NAMESPACE_SCOPE="default"

SA_YAML_FILE=testSA.yaml
ROLE_YAML_FILE=testRole.yaml
RB_YAML_FILE=testRB.yaml

cat >"$SA_YAML_FILE" <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SERVICE_ACCOUNT_NAME}
  namespace: ${NAMESPACE_SCOPE}
EOF

cat >"$ROLE_YAML_FILE" <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${SERVICE_ACCOUNT_NAME}-test-role
  namespace: ${NAMESPACE_SCOPE}  # Same as the ServiceAccount namespace
rules:
- apiGroups: ["batch"]
  resources: ["jobs"]
  verbs: ["create", "get", "list", "watch", "delete"]
EOF

cat >"$RB_YAML_FILE" <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${SERVICE_ACCOUNT_NAME}-test-rolebinding
  namespace: ${NAMESPACE_SCOPE}   # Same as the Role and ServiceAccount namespace
subjects:
- kind: ServiceAccount
  name: ${SERVICE_ACCOUNT_NAME}   # Name of the ServiceAccount
  namespace: ${NAMESPACE_SCOPE}   # Namespace of the ServiceAccount
roleRef:
  kind: Role
  name: ${SERVICE_ACCOUNT_NAME}-spawner-role  # Name of the Role
  apiGroup: rbac.authorization.k8s.io
EOF

# ======= Apply =========
kubectl apply -f "$SA_YAML_FILE"
kubectl apply -f "$ROLE_YAML_FILE"
kubectl apply -f "$RB_YAML_FILE"

# ======= Cleanup =========
kubectl delete -f "$RB_YAML_FILE"
kubectl delete -f "$ROLE_YAML_FILE"
kubectl delete -f "$SA_YAML_FILE"

rm -f "$RB_YAML_FILE"
rm -f "$ROLE_YAML_FILE"
rm -f "$SA_YAML_FILE"
