import boto3
import datetime
import time

def delete_old_amis():
    ec2_client = boto3.client('ec2')

    # Get all AMIs owned by the account
    response = ec2_client.describe_images(
        Owners=['self'],
        Filters=[
            {
                'Name': 'tag:ScheduledForDelete',
                'Values': ['True']
            }
        ]
    )
    for image in response['Images']:
        ami_id = image['ImageId']
        creation_date = image['CreationDate']  # Format: YYYY-MM-DDTHH:MM:SS.SSSZ
        creation_date = datetime.datetime.strptime(creation_date, "%Y-%m-%dT%H:%M:%S.%fZ")

        # Get AMI tags
        tags = {tag['Key']: tag['Value'] for tag in image.get('Tags', [])}
        
        if tags.get('ScheduledForDelete') != 'True':
            continue  # Skip AMIs that aren't marked for deletion

        days_to_keep = int(tags.get('DaysToKeep', 30))  # Default to 30 if not present
        expiration_date = creation_date + datetime.timedelta(days=days_to_keep)
        time_now = datetime.datetime.now(datetime.timezone.utc)
        time_now = time_now.replace(tzinfo=None, microsecond=0)
        if time_now >= expiration_date:
            print(f"Deleting AMI: {ami_id} (Created: {creation_date}, Expired: {expiration_date})")

            # Deregister AMI
            ec2_client.deregister_image(ImageId=ami_id)
            time.sleep(5)
            
            # Get associated snapshots
            for block_device in image.get('BlockDeviceMappings', []):
                if 'Ebs' in block_device:
                    snapshot_id = block_device['Ebs']['SnapshotId']
                    print(f"Deleting snapshot: {snapshot_id}")
                    ec2_client.delete_snapshot(SnapshotId=snapshot_id)

if __name__ == "__main__":
    delete_old_amis()
