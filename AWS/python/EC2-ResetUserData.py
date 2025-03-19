import boto3
from botocore.exceptions import ClientError
import time

# Initialize the EC2 client
ec2 = boto3.client('ec2')

def get_instances():
    """
    Retrieve all EC2 instances
    """
    try:
        response = ec2.describe_instances()
        instances = []
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instances.append(instance)
        return instances
    except ClientError as e:
        print(f"Error retrieving EC2 instances: {e}")
        return []

def get_instance_name(instance_id):
    """
    Retrieve the name tag for the EC2 instance
    """
    try:
        response = ec2.describe_instances(InstanceIds=[instance_id])
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                # Check for 'Name' tag
                for tag in instance.get('Tags', []):
                    if tag['Key'] == 'Name':
                        return tag['Value']
        return "No Name Tag"
    except ClientError as e:
        print(f"Error retrieving name for instance {instance_id}: {e}")
        return "Unknown Name"

def stop_instance(instance_id):
    """
    Stop the EC2 instance and wait for the instance to stop
    """
    try:
        instance_name = get_instance_name(instance_id)
        print(f"Stopping instance: {instance_id} ({instance_name})")
        ec2.stop_instances(InstanceIds=[instance_id])
        # Wait until the instance is stopped
        waiter = ec2.get_waiter('instance_stopped')
        waiter.wait(InstanceIds=[instance_id])
        print(f"Instance {instance_id} ({instance_name}) has stopped.")
    except ClientError as e:
        print(f"Error stopping instance {instance_id} ({instance_name}): {e}")

def start_instance(instance_id):
    """
    Start the EC2 instance and wait for the instance to start
    """
    try:
        instance_name = get_instance_name(instance_id)
        print(f"Starting instance: {instance_id} ({instance_name})")
        ec2.start_instances(InstanceIds=[instance_id])
        # Wait until the instance is running
        waiter = ec2.get_waiter('instance_running')
        waiter.wait(InstanceIds=[instance_id])
        print(f"Instance {instance_id} ({instance_name}) is now running.")
    except ClientError as e:
        print(f"Error starting instance {instance_id} ({instance_name}): {e}")

def modify_user_data(instance_id):
    """
    Modify the EC2 instance's user data to 'null' (empty string)
    """
    try:
        instance_name = get_instance_name(instance_id)
        print(f"Modifying user data for instance {instance_id} ({instance_name}) to null...")
        # Set user data to null (empty string)
        ec2.modify_instance_attribute(InstanceId=instance_id, UserData={'Value': ''})
    except ClientError as e:
        print(f"Error modifying user data for instance {instance_id} ({instance_name}): {e}")

def check_user_data(instance_id):
    """
    Check if the user data for the instance is empty.
    """
    try:
        response = ec2.describe_instance_attribute(InstanceId=instance_id, Attribute='userData')
        user_data = (response.get('UserData', None)).get('Value', None)
        return user_data == '' or user_data is None
    except ClientError as e:
        print(f"Error checking user data for instance {instance_id}: {e}")
        return False

def process_instances():
    """
    Process each EC2 instance
    """
    instances = get_instances()
    
    for instance in instances:
        instance_id = instance['InstanceId']
        state = instance['State']['Name']
        instance_name = get_instance_name(instance_id)
               
        # Check if user data is already empty
        if check_user_data(instance_id):
            print(f"Instance {instance_id} ({instance_name}) already has empty user data. Skipping modification.")
            continue
        
        if state == 'stopped':
            print(f"Instance {instance_id} ({instance_name}) is stopped. Modifying user data...")
            modify_user_data(instance_id)
            # Ensure instance remains stopped
        
        elif state == 'running':
            user_input = input(f"Instance {instance_id} ({instance_name}) is running. Do you want to stop it, modify user data, and restart it? (y/n): ")
            if user_input.lower() == 'y':
                stop_instance(instance_id)
                modify_user_data(instance_id)
                start_instance(instance_id)
            else:
                print(f"Skipping modification for running instance {instance_id} ({instance_name}).")
        else:
            print(f"Instance {instance_id} ({instance_name}) is in an unknown state: {state}. Skipping.")

if __name__ == '__main__':
    process_instances()
