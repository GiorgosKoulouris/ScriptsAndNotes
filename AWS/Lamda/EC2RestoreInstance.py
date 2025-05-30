import boto3
import time

ec2 = boto3.client('ec2')


def get_instance_details(instance_id):
    response = ec2.describe_instances(InstanceIds=[instance_id])
    instance = response['Reservations'][0]['Instances'][0]
    return instance


def get_ami_snapshot_mappings(ami_id):
    response = ec2.describe_images(ImageIds=[ami_id])
    mappings = response['Images'][0]['BlockDeviceMappings']
    return {m['DeviceName']: m['Ebs']['SnapshotId'] for m in mappings if 'Ebs' in m}


def get_instance_volume_mappings(instance):
    return {v['DeviceName']: v['Ebs']['VolumeId'] for v in instance['BlockDeviceMappings']}


def validate_snapshots(snapshot_ids):
    response = ec2.describe_snapshots(SnapshotIds=snapshot_ids)
    return all(snap['State'] == 'completed' for snap in response['Snapshots'])


def stop_instance(instance_id):
    ec2.stop_instances(InstanceIds=[instance_id])
    waiter = ec2.get_waiter('instance_stopped')
    waiter.wait(InstanceIds=[instance_id])


def create_volumes(snapshot_mappings, availability_zone):
    volumes = {}
    for device, snapshot_id in snapshot_mappings.items():
        response = ec2.create_volume(
            SnapshotId=snapshot_id,
            AvailabilityZone=availability_zone,
            VolumeType='gp3'
        )
        volumes[device] = response['VolumeId']
    return volumes


def swap_volumes(instance_id, old_volumes, new_volumes, reason):
    for device, old_volume_id in old_volumes.items():
        new_volume_id = new_volumes.get(device)
        if new_volume_id:
            ec2.detach_volume(VolumeId=old_volume_id, InstanceId=instance_id, Force=True)
            ec2.get_waiter('volume_available').wait(VolumeIds=[old_volume_id])
            
            old_tags = ec2.describe_volumes(VolumeIds=[old_volume_id])['Volumes'][0]['Tags']
            old_name = next((t['Value'] for t in old_tags if t['Key'] == 'Name'), 'instance_id')
            ec2.create_tags(Resources=[old_volume_id], Tags=[{'Key': 'Name', 'Value': f"{old_name}_OLD_{reason}"}])
            
            ec2.attach_volume(VolumeId=new_volume_id, InstanceId=instance_id, Device=device)
            ec2.get_waiter('volume_in_use').wait(VolumeIds=[new_volume_id])
            
            ec2.create_tags(Resources=[new_volume_id], Tags=old_tags)
            ec2.create_tags(Resources=[new_volume_id], Tags=[{'Key': 'Name', 'Value': f"{old_name}_NEW_{reason}"}])


def restore_instance(instance_id, ami_id, restore_all_disks, reason):
    instance = get_instance_details(instance_id)
    original_state = instance['State']['Name']
    availability_zone = instance['Placement']['AvailabilityZone']
    
    ami_snapshots = get_ami_snapshot_mappings(ami_id)
    instance_volumes = get_instance_volume_mappings(instance)
    
    if not restore_all_disks:
        root_device = instance['RootDeviceName']
        ami_snapshots = {root_device: ami_snapshots[root_device]}
    
    if not validate_snapshots(list(ami_snapshots.values())):
        raise ValueError("One or more AMI snapshots are missing or incomplete.")
    
    stop_instance(instance_id)
    new_volumes = create_volumes(ami_snapshots, availability_zone)
    swap_volumes(instance_id, instance_volumes, new_volumes, reason)
    
    if original_state == 'running':
        ec2.start_instances(InstanceIds=[instance_id])

def main(event, context):
    instance_id = event['instance_id']
    ami_id = event['ami_id']
    restore_all_disks = event['restore_all_disks']
    reason = event['reason']
    
    if not ami_id.startswith('ami-'):
        print(f'Invalid AMI ID ({ami_id}). Exiting...')
        quit()
        
    if (restore_all_disks.lower() == 'true'):
        restore_all_disks = True
    elif (restore_all_disks.lower() == 'false'):
        restore_all_disks = False
    else:
        print(f'Invalid option: (RestoreAllDisks). Valid options are true, false. Exiting...')
        quit()
        
    if reason == '':
        print('Reason cannot be empty. Exiting...')
        quit()

    restore_instance(instance_id, ami_id, restore_all_disks, reason)
    
if __name__ == "__main__":
    event = {
        'instance_id': 'i-0d95989d8b4551f2c',
        'ami_id': 'ami-0e19f7cf1665bb486',
        'restore_all_disks': 'true',
        'reason': 'TestRestore'
    }
    main(event, None)

# Example usage:
# restore_instance('i-0123456789abcdef0', 'ami-0abcdef1234567890', True, 'SystemRestore')
