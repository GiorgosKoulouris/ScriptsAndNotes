import boto3
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
        
def get_ec2_instance_name(instance_id, ec2_client):
    """Retrieve the 'Name' tag of the EC2 instance."""
    try:
        response = ec2_client.describe_instances(InstanceIds=[instance_id])
        reservations = response['Reservations']
        for reservation in reservations:
            for instance in reservation['Instances']:
                # Look for the 'Name' tag
                for tag in instance.get('Tags', []):
                    if tag['Key'] == 'Name':
                        return tag['Value']
    except Exception as e:
        print(f"Error fetching instance name for {instance_id}: {e}")
        return None

def main(region):
    ec2_client = init_aws_client(region)
    # Describe all Elastic IPs in the region
    try:
        eips = ec2_client.describe_addresses()
    except Exception as e:
        print(f"Error describing Elastic IPs: {e}")
        exit(1)

    # Iterate through each Elastic IP
    for eip in eips.get('Addresses', []):
        allocation_id = eip['AllocationId']  # This is the ID we need for tagging
        if 'InstanceId' in eip:
            # EIP is attached to an EC2 instance
            instance_id = eip['InstanceId']
            instance_name = get_ec2_instance_name(instance_id, ec2_client)
            if instance_name:
                # Tag the EIP with the instance name
                eni_name = f"{instance_name}_EIP"
                ec2_client.create_tags(
                    Resources=[allocation_id],
                    Tags=[{'Key': 'Name', 'Value': eni_name}]
                )
                print(f"Tagged EIP {allocation_id} with Name: {eni_name}")
            else:
                print(f"Failed to retrieve instance name for {instance_id}")
        else:
            # EIP is not attached to any instance
            ec2_client.create_tags(
                Resources=[allocation_id],
                Tags=[{'Key': 'Name', 'Value': 'Unattached'}]
            )
            print(f"Tagged EIP {allocation_id} with Name: Unattached")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--region", type=str, required=False, help="Region Name"
    )
    args = parser.parse_args()
    region = args.region
    main(region)
