import boto3
import argparse
import sys


def get_instance_details(region):
    # Create a boto3 EC2 client for the given region
    ec2_client = boto3.client("ec2", region_name=region)

    # Describe all instances in the region
    instances = ec2_client.describe_instances()

    instance_details = []

    # Collect instance names and attached EBS volumes
    for reservation in instances["Reservations"]:
        for instance in reservation["Instances"]:
            instance_id = instance["InstanceId"]
            instance_name = None
            volumes = []

            # Check for instance name (if available)
            if "Tags" in instance:
                for tag in instance["Tags"]:
                    if tag["Key"] == "Name":
                        instance_name = tag["Value"]

            # Get all attached volumes
            for block_device in instance.get("BlockDeviceMappings", []):
                volume_id = block_device["Ebs"]["VolumeId"]
                if block_device.get("DeviceName", "").startswith("/dev/xvda") or block_device.get("DeviceName", "").startswith("/dev/sda1"):
                    volumes.append(
                        {
                            "VolumeId": volume_id,
                            "Device": block_device["DeviceName"],
                            "IsRoot": True,
                        }
                    )
                else:
                    volumes.append(
                        {
                            "VolumeId": volume_id,
                            "Device": block_device["DeviceName"],
                            "IsRoot": False,
                        }
                    )

            instance_details.append(
                {
                    "InstanceId": instance_id,
                    "InstanceName": instance_name,
                    "Volumes": volumes,
                }
            )

    return instance_details


def get_volume_name(volume_id, ec2_client):
    # Get volume details
    volume_info = ec2_client.describe_volumes(VolumeIds=[volume_id])
    volume = volume_info["Volumes"][0]
    current_name = None

    # Check for the 'Name' tag on the volume
    if "Tags" in volume:
        for tag in volume["Tags"]:
            if tag["Key"] == "Name":
                current_name = tag["Value"]

    return current_name


def rename_volume(volume_id, new_name, ec2_client):
    # Rename the volume by adding a tag with the new name
    ec2_client.create_tags(
        Resources=[volume_id], Tags=[{"Key": "Name", "Value": new_name}]
    )
    print(f"Renamed volume {volume_id} to {new_name}")


def main(region):
    # Create boto3 EC2 client
    ec2_client = boto3.client("ec2", region_name=region)

    # Get instance and attached volumes info
    instance_details = get_instance_details(region)

    for instance in instance_details:
        instance_name = instance["InstanceName"]
        if not instance_name:
            instance_name = instance[
                "InstanceId"
            ]  # Fallback to InstanceId if Name is missing

        for volume in instance["Volumes"]:
            volume_id = volume["VolumeId"]
            is_root = volume["IsRoot"]

            # Get the current name of the volume
            current_name = get_volume_name(volume_id, ec2_client)

            # Skip renaming if the volume already has a name
            if current_name:
                print(
                    f"Skipping volume {volume_id} as it already has a name: {current_name}"
                )
                continue

            # Determine the new volume name based on whether it's an OS disk or Data disk
            if is_root:
                new_name = f"{instance_name}_OS"
            else:
                new_name = f"{instance_name}_DataDisk"

            # Rename the volume
            rename_volume(volume_id, new_name, ec2_client)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: python {sys.argv[0]} <region>")
        sys.exit(1)
        
    # Set up argument parser
    parser = argparse.ArgumentParser(
        description="Rename EBS volumes attached to EC2 instances"
    )
    parser.add_argument("region", type=str, help="AWS region to operate in")

    # Parse arguments
    args = parser.parse_args()

    # Run the script with the provided region
    main(args.region)