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

def enable_termination_protection(ec2_client):
        
    # Get all instances
    instances = ec2_client.describe_instances()
    
    for reservation in instances['Reservations']:
        for instance in reservation['Instances']:
            instance_id = instance['InstanceId']
            name_tag = next((tag['Value'] for tag in instance.get('Tags', []) if tag['Key'] == 'Name'), "Unnamed")
            
            # Check if termination protection is already enabled
            attr = ec2_client.describe_instance_attribute(InstanceId=instance_id, Attribute='disableApiTermination')
            termination_protection = attr['DisableApiTermination']['Value']
            
            if termination_protection:
                print(f"Termination protection already enabled for instance: {name_tag} ({instance_id})")
            else:
                try:
                    ec2_client.modify_instance_attribute(
                        InstanceId=instance_id,
                        DisableApiTermination={'Value': True}
                    )
                    print(f"Enabled termination protection for instance: {name_tag} ({instance_id})")
                except Exception as e:
                    print(f"Failed to enable termination protection for {name_tag} ({instance_id}): {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--region", type=str, required=False, help="Region Name"
    )
    args = parser.parse_args()
    region = args.region
    ec2_client = init_aws_client(region)
    enable_termination_protection(ec2_client)
