import boto3
from botocore.exceptions import ClientError
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


def get_instances(ec2_client):
    """
    Retrieve all EC2 instances
    """
    try:
        response = ec2_client.describe_instances()
        instances = []
        for reservation in response["Reservations"]:
            for instance in reservation["Instances"]:
                instances.append(instance)
        return instances
    except ClientError as e:
        print(f"Error retrieving EC2 instances: {e}")
        return []


def get_instance_name(instance_id, ec2_client):
    """
    Retrieve the name tag for the EC2 instance
    """
    try:
        response = ec2_client.describe_instances(InstanceIds=[instance_id])
        for reservation in response["Reservations"]:
            for instance in reservation["Instances"]:
                # Check for 'Name' tag
                for tag in instance.get("Tags", []):
                    if tag["Key"] == "Name":
                        return tag["Value"]
        return "No Name Tag"
    except ClientError as e:
        print(f"Error retrieving name for instance {instance_id}: {e}")
        return "Unknown Name"


def stop_instance(instance_id, ec2_client):
    """
    Stop the EC2 instance and wait for the instance to stop
    """
    try:
        instance_name = get_instance_name(instance_id, ec2_client)
        print(f"Stopping instance: {instance_id} ({instance_name})")
        ec2_client.stop_instances(InstanceIds=[instance_id])
        # Wait until the instance is stopped
        waiter = ec2_client.get_waiter("instance_stopped")
        waiter.wait(InstanceIds=[instance_id])
        print(f"Instance {instance_id} ({instance_name}) has stopped.")
    except ClientError as e:
        print(f"Error stopping instance {instance_id} ({instance_name}): {e}")


def start_instance(instance_id, ec2_client):
    """
    Start the EC2 instance and wait for the instance to start
    """
    try:
        instance_name = get_instance_name(instance_id, ec2_client)
        print(f"Starting instance: {instance_id} ({instance_name})")
        ec2_client.start_instances(InstanceIds=[instance_id])
        # Wait until the instance is running
        waiter = ec2_client.get_waiter("instance_running")
        waiter.wait(InstanceIds=[instance_id])
        print(f"Instance {instance_id} ({instance_name}) is now running.")
    except ClientError as e:
        print(f"Error starting instance {instance_id} ({instance_name}): {e}")


def modify_user_data(instance_id, ec2_client):
    """
    Modify the EC2 instance's user data to 'null' (empty string)
    """
    try:
        instance_name = get_instance_name(instance_id, ec2_client)
        print(
            f"Modifying user data for instance {instance_id} ({instance_name}) to null..."
        )
        # Set user data to null (empty string)
        ec2_client.modify_instance_attribute(
            InstanceId=instance_id, UserData={"Value": ""}
        )
    except ClientError as e:
        print(
            f"Error modifying user data for instance {instance_id} ({instance_name}): {e}"
        )


def check_user_data(instance_id, ec2_client):
    """
    Check if the user data for the instance is empty.
    """
    try:
        response = ec2_client.describe_instance_attribute(
            InstanceId=instance_id, Attribute="userData"
        )
        user_data = (response.get("UserData", None)).get("Value", None)
        return user_data == "" or user_data is None
    except ClientError as e:
        print(f"Error checking user data for instance {instance_id}: {e}")
        return False


def process_instances(ec2_client):
    """
    Process each EC2 instance
    """
    instances = get_instances(ec2_client)

    for instance in instances:
        instance_id = instance["InstanceId"]
        state = instance["State"]["Name"]
        instance_name = get_instance_name(instance_id, ec2_client)

        # Check if user data is already empty
        if check_user_data(instance_id, ec2_client):
            print(
                f"Instance {instance_id} ({instance_name}) already has empty user data. Skipping modification."
            )
            continue

        if state == "stopped":
            print(
                f"Instance {instance_id} ({instance_name}) is stopped. Modifying user data..."
            )
            modify_user_data(instance_id, ec2_client)
            # Ensure instance remains stopped

        elif state == "running":
            user_input = input(
                f"Instance {instance_id} ({instance_name}) is running. Do you want to stop it, modify user data, and restart it? (y/n): "
            )
            if user_input.lower() == "y":
                stop_instance(instance_id, ec2_client)
                modify_user_data(instance_id, ec2_client)
                start_instance(instance_id, ec2_client)
            else:
                print(
                    f"Skipping modification for running instance {instance_id} ({instance_name})."
                )
        else:
            print(
                f"Instance {instance_id} ({instance_name}) is in an unsupported state: {state}. Skipping."
            )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--region", type=str, required=False, help="Region Name")
    args = parser.parse_args()
    region = args.region
    ec2_client = init_aws_client(region)
    process_instances(ec2_client)
