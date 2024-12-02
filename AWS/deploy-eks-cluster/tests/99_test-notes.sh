# ========== Configure the pod to use the service account ========
# https://docs.aws.amazon.com/eks/latest/userguide/pod-configuration.html

source ../00_variables.sh

SERVICE_ACCOUNT_NAME="test-pod-sa"
NAMESPACE_SCOPE="default"

EFS_ID="fs-XXXXXXX" # only if there is not stored on ../00_variables.sh

DEP_YAML_FILE=testDeployment.yaml
PV_YAML_FILE=testPV.yaml

cat >"$DEP_YAML_FILE" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-role-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-role-app
  template:
    metadata:
      labels:
        app: test-role-app
    spec:
      serviceAccountName: ${SERVICE_ACCOUNT_NAME}
      volumes:
      - name: test-efs
        persistentVolumeClaim:
          claimName: test-efs
      containers:
      - name: test-role-app
        image: public.ecr.aws/nginx/nginx:1.22
        volumeMounts:
        - name: test-efs
          mountPath: /testPath
EOF

cat >"$PV_YAML_FILE" <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: test-efs
spec:
  capacity:
    storage: 5Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: efs-sc
  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${EFS_ID}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-efs
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-sc
  resources:
    requests:
      storage: 5Gi
EOF

kubectl apply -f "$PV_YAML_FILE"
kubectl apply -f "$DEP_YAML_FILE"

kubectl describe pod $(kubectl get pods | grep test-role-app | awk -F' ' '{print $1}')
# If your service account has IAM roles, verify this was
kubectl describe pod $(kubectl get pods | grep test-role-app | awk -F' ' '{print $1}') | grep -E "(AWS_ROLE_ARN:|AWS_WEB_IDENTITY_TOKEN_FILE)"

# ============== Cleanup ==================
kubectl delete -f "$DEP_YAML_FILE"
kubectl delete -f "$PV_YAML_FILE"

rm -f "$DEP_YAML_FILE"
rm -f "$PV_YAML_FILE"
