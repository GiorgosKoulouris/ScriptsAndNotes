# ------------ Store image to S3 bucket ----------------------------
# https://docs.aws.amazon.com/cli/latest/reference/ec2/create-store-image-task.html

aws ec2 create-store-image-task \
    --image-id VALUE \
    --bucket VALUE

# ------------ Restore image from S3 ----------------------------
# https://docs.aws.amazon.com/cli/latest/reference/ec2/create-restore-image-task.html

aws ec2 create-restore-image-task \
    --bucket VALUE \
    --object-key VALUE \
    --name VALUE

# ------------- Describre Store Image Tasks -----------
# https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-store-image-tasks.html

aws ec2 describe-store-image-tasks
