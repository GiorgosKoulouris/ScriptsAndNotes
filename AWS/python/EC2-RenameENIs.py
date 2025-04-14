import boto3
import argparse
from botocore.exceptions import ClientError
import sys

def init_aws_client(region):
    """Initializes EC2 boto client

    :param region: AWS Region
    :type region: string
    :return: EC2 client, EFS client
    :rtype: boto_client, boto_client
    """
    
    try:
        if region:   
            ec2_client = boto3.client("ec2", region_name=region)
            efs_client = boto3.client("efs", region_name=region)
        else:
            ec2_client = boto3.client("ec2")
            efs_client = boto3.client("efs")
        print("Successfully created AWS clients")
        return ec2_client, efs_client
    except Exception as e:
        print("Failed to create AWS clients")
        exit(1)
        
def get_eni_attachment_info(eni_id, ec2_client, efs_client):
    """Fetches the attachment information for an ENI (Elastic Network Interface)."""
    try:
        response = ec2_client.describe_network_interfaces(NetworkInterfaceIds=[eni_id])
        eni = response['NetworkInterfaces'][0]
        
        attachment = eni.get('Attachment', {})
        interface_type = eni['InterfaceType']
        
        
        instance_id = eni.get('Attachment', {}).get('InstanceId', None)
        
        if instance_id:
            return 'EC2', instance_id
        elif interface_type == 'efs':
            efs_id = eni.get('Description', '').split(' ')[4]
            efs_tags = efs_client.list_tags_for_resource(ResourceId=efs_id)
            efs_name_tag = 'EFS'
            for tag in efs_tags.get('Tags', []):
                if tag['Key'] == 'Name':
                    efs_name_tag = tag['Value']
            return 'EFS', efs_name_tag
        else:
            return None, None
    except ClientError as e:
        print(f"Error fetching ENI attachment info: {e}")
        return None, None

def get_instance_name(instance_id, ec2_client):
    """Fetches the instance name based on the instance ID."""
    try:
        response = ec2_client.describe_instances(InstanceIds=[instance_id])
        instance = response['Reservations'][0]['Instances'][0]
        instance_name = None
        for tag in instance.get('Tags', []):
            if tag['Key'] == 'Name':
                instance_name = tag['Value']
        # Fallback to instance ID if no 'Name' tag is found
        return instance_name if instance_name else instance_id
    except ClientError as e:
        print(f"Error fetching instance name for {instance_id}: {e}")
        return instance_id  # Fallback to instance ID if an error occurs

def add_eni_tag(eni_id, tag_key, tag_value, ec2_client):
    """Adds a 'Name' tag to the ENI with the specified value."""
    try:
        # Adding the 'Name' tag to the ENI
        response = ec2_client.create_tags(
            Resources=[eni_id],
            Tags=[{'Key': tag_key, 'Value': tag_value}]
        )
        print(f"Added tag to ENI {eni_id}: {tag_key} = {tag_value}")
    except ClientError as e:
        print(f"Error adding tag to ENI {eni_id}: {e}")

def main(region):
    # Initialize AWS clients for the specified region
    ec2_client, efs_client = init_aws_client(region)

    # List all network interfaces in the specified region
    try:
        response = ec2_client.describe_network_interfaces()
        for eni in response['NetworkInterfaces']:
            eni_id = eni['NetworkInterfaceId']
            
            # Skip ENIs that already have a 'Name' tag
            existing_tags = eni.get('TagSet', [])
            existing_name_tag = ''
            for tag in existing_tags:
                if tag['Key'] == 'Name':
                    existing_name_tag = tag['Value']
            if existing_name_tag == '':
                attachment_type, attachment_id = get_eni_attachment_info(eni_id, ec2_client, efs_client)
                if attachment_type == 'EC2' and attachment_id:
                    instance_name = get_instance_name(attachment_id, ec2_client)
                    tag_value = f"{instance_name}_ENI"  # Format the name tag value
                    add_eni_tag(eni_id, 'Name', tag_value, ec2_client)
                elif attachment_type == 'EFS':
                    tag_value = f"{attachment_id}_EFS_ENI"  # Format the name tag value
                    add_eni_tag(eni_id, 'Name', tag_value, ec2_client)
                else:
                    print(f"ENI {eni_id} is not attached to EC2 or EFS, skipping.")
            else:
                print(f"ENI {eni_id} already has a Name tag, skipping ({existing_name_tag}).")
    except ClientError as e:  
        print(f"Error describing network interfaces: {e}")

if __name__ == '__main__':       
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--region", type=str, required=False, help="Region Name"
    )
    args = parser.parse_args()
    region = args.region
    
    # Run the main function with the specified region
    main(args.region)
