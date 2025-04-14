import boto3
import time
import argparse

def init_aws_client(region):
    """Initializes EC2 boto client

    :param region: AWS Region
    :type region: string
    :return: EC2 client
    :rtype: boto_client
    """
    
    try:
        if region:   
            ec2_client = boto3.client("ec2", region_name=region)
        else:
            ec2_client = boto3.client("ec2")
        print("Successfully created AWS client")
        return ec2_client
    except Exception as e:
        print("Failed to create AWS client")
        exit(1)

def create_snapshot(volume_id, ec2_client):
    """Create a snapshot of the unencrypted volume and wait for it to become available."""
    print(f"Creating snapshot for volume {volume_id}...")
    response = ec2_client.create_snapshot(
        VolumeId=volume_id,
        Description=f"Snapshot for volume {volume_id} for encryption"
    )
    snapshot_id = response['SnapshotId']
    print(f"Snapshot created: {snapshot_id}")
    
    # Wait for snapshot to be available
    print(f"Waiting for snapshot {snapshot_id} to become available...")
    wait_for_snapshot(snapshot_id, ec2_client)
    print(f"Snapshot {snapshot_id} is now available.")
    return snapshot_id

def wait_for_snapshot(snapshot_id, ec2_client):
    """Wait for the snapshot to be available."""
    while True:
        response = ec2_client.describe_snapshots(SnapshotIds=[snapshot_id])
        snapshot_state = response['Snapshots'][0]['State']
        if snapshot_state == 'completed':
            break
        print(f"Snapshot {snapshot_id} is in state {snapshot_state}. Waiting...")
        time.sleep(10)

def create_encrypted_volume_from_snapshot(snapshot_id, volume_type, iops, throughput, encryption_key_id, az, ec2_client):
    """Create an encrypted volume from the snapshot with the same specs as the original volume."""
    print(f"Creating encrypted volume from snapshot {snapshot_id} with type {volume_type}...")
    params = {
        'SnapshotId': snapshot_id,
        'VolumeType': volume_type,  # Set the same type as the original volume
        'AvailabilityZone': az,    # Ensure the volume is created in the same AZ
    }
    
    # For gp3 volumes, add IOPS and throughput if applicable
    if volume_type == 'gp3':
        params['Iops'] = iops
        params['Throughput'] = throughput
    
    if encryption_key_id:
        params['KmsKeyId'] = encryption_key_id
        params['Encrypted'] = True

    response = ec2_client.create_volume(**params)
    encrypted_volume_id = response['VolumeId']
    print(f"Encrypted volume created: {encrypted_volume_id}")
    return encrypted_volume_id

def delete_snapshot(snapshot_id, ec2_client):
    """Delete the snapshot after the volume has been created."""
    print(f"Deleting snapshot {snapshot_id}...")
    ec2_client.delete_snapshot(SnapshotId=snapshot_id)
    print(f"Snapshot {snapshot_id} deleted.")

def get_device_name_for_volume(volume_id, ec2_client):
    """Get the device name for the attached volume."""
    response = ec2_client.describe_volumes(VolumeIds=[volume_id])
    volume = response['Volumes'][0]
    
    if 'Attachments' in volume and len(volume['Attachments']) > 0:
        device_name = volume['Attachments'][0]['Device']
        return device_name
    else:
        raise ValueError(f"Volume {volume_id} is not attached to any instance.")

def get_volume_specs_and_tags(volume_id, ec2_client):
    """Get the specifications of the volume (type, IOPS, throughput) and any tags."""
    response = ec2_client.describe_volumes(VolumeIds=[volume_id])
    volume = response['Volumes'][0]
    
    volume_type = volume['VolumeType']
    iops = volume.get('Iops', None)
    throughput = volume.get('Throughput', None)
    az = volume['AvailabilityZone']
    
    # Retrieve the Name tag if it exists
    name = None
    if 'Tags' in volume:
        for tag in volume['Tags']:
            if tag['Key'] == 'Name':
                name = tag['Value']
                break
    
    return volume_type, iops, throughput, az, name

def stop_instance(instance_id, ec2_client):
    """Stop the EC2 instance."""
    print(f"Stopping instance {instance_id}...")
    ec2_client.stop_instances(InstanceIds=[instance_id])
    print(f"Instance {instance_id} stopped.")
    
    # Wait until the instance is stopped
    while True:
        response = ec2_client.describe_instances(InstanceIds=[instance_id])
        state = response['Reservations'][0]['Instances'][0]['State']['Name']
        if state == 'stopped':
            break
        time.sleep(5)

def start_instance(instance_id, ec2_client):
    """Start the EC2 instance."""
    print(f"Starting instance {instance_id}...")
    ec2_client.start_instances(InstanceIds=[instance_id])
    print(f"Instance {instance_id} started.")
    
    # Wait until the instance is running
    while True:
        response = ec2_client.describe_instances(InstanceIds=[instance_id])
        state = response['Reservations'][0]['Instances'][0]['State']['Name']
        if state == 'running':
            break
        time.sleep(5)

def detach_and_attach_volumes(instance_id, original_volume_id, encrypted_volume_id, device_name, ec2_client):
    """Detach the original volume and attach the encrypted volume to the instance."""
    # Detach original volume
    print(f"Detaching volume {original_volume_id} from instance {instance_id}...")
    ec2_client.detach_volume(VolumeId=original_volume_id)
    print(f"Volume {original_volume_id} detached.")
    
    # Wait until the volume is detached
    print(f"Waiting for volume {original_volume_id} to be detached...")
    while True:
        response = ec2_client.describe_volumes(VolumeIds=[original_volume_id])
        volume_state = response['Volumes'][0]['State']
        if volume_state == 'available':
            break
        time.sleep(5)
    
    # Attach encrypted volume to the same device as the original
    print(f"Attaching encrypted volume {encrypted_volume_id} to instance {instance_id} at device {device_name}...")
    response = ec2_client.attach_volume(
        VolumeId=encrypted_volume_id,
        InstanceId=instance_id,
        Device=device_name
    )
    print(f"Encrypted volume {encrypted_volume_id} attached at device {device_name}.")

def rename_original_volume(volume_id, original_name, ec2_client):
    """Rename the original volume by appending '_Unencrypted'."""
    new_name = f"{original_name}_Unencrypted"
    print(f"Renaming original volume {volume_id} to {new_name}...")
    ec2_client.create_tags(
        Resources=[volume_id],
        Tags=[{'Key': 'Name', 'Value': new_name}]
    )
    print(f"Original volume {volume_id} renamed to {new_name}.")

def rename_encrypted_volume(encrypted_volume_id, original_name, ec2_client):
    """Rename the new encrypted volume to the same name as the original."""
    if original_name:
        print(f"Renaming encrypted volume {encrypted_volume_id} to {original_name}...")
        ec2_client.create_tags(
            Resources=[encrypted_volume_id],
            Tags=[{'Key': 'Name', 'Value': original_name}]
        )
        print(f"Encrypted volume {encrypted_volume_id} renamed to {original_name}.")

def encrypt_ebs_volume(volume_id, encryption_key_id, ec2_client):
    """Main function to encrypt an EBS volume."""
    # Create snapshot
    snapshot_id = create_snapshot(volume_id, ec2_client)
    
    # Get the specifications of the original volume and its tags
    volume_type, iops, throughput, az, original_name = get_volume_specs_and_tags(volume_id, ec2_client)
    
    # Create encrypted volume from snapshot with the same specs
    encrypted_volume_id = create_encrypted_volume_from_snapshot(snapshot_id, volume_type, iops, throughput, encryption_key_id, az, ec2_client)
    
    # Delete the snapshot
    delete_snapshot(snapshot_id, ec2_client)
    
    # Get the attachment details for the original volume
    volume_info = ec2_client.describe_volumes(VolumeIds=[volume_id])['Volumes'][0]
    
    # If the volume is attached to an instance, get the device name
    if volume_info['State'] == 'in-use':
        instance_id = volume_info['Attachments'][0]['InstanceId']
        device_name = get_device_name_for_volume(volume_id, ec2_client)
        
        # Handle instance stop/start if it's a root (OS) volume
        if device_name == '/dev/xvda' or device_name == '/dev/sda1':
            print(f"Volume {volume_id} is the OS disk. Stopping instance {instance_id}...")
            stop_instance(instance_id, ec2_client)
            detach_and_attach_volumes(instance_id, volume_id, encrypted_volume_id, device_name, ec2_client)
            start_instance(instance_id, ec2_client)
        else:
            detach_and_attach_volumes(instance_id, volume_id, encrypted_volume_id, device_name, ec2_client)
    
    # Rename the original volume to include '_Unencrypted' and apply the same name to the encrypted volume
    if original_name:
        rename_original_volume(volume_id, original_name, ec2_client)
        rename_encrypted_volume(encrypted_volume_id, original_name, ec2_client)

    print(f"Encryption process complete for volume {volume_id}. Encrypted volume ID: {encrypted_volume_id}")

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--region", type=str, required=False, help="Region Name"
    )
    parser.add_argument(
        "--vol-id", type=str, required=True, help="Volume ID"
    )
    parser.add_argument(
        "--key-id", type=str, required=True, help="Encryption key ID to use for encryption"
    )
    args = parser.parse_args()
    region = args.region
    ec2_client = init_aws_client(region)

    volume_id = args.vol_id
    encryption_key_id = args.key_id

    encrypt_ebs_volume(volume_id, encryption_key_id, ec2_client)
