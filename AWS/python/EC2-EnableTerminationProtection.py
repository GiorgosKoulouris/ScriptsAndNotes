import boto3

def enable_termination_protection():
    ec2_client = boto3.client('ec2')
    
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
    enable_termination_protection()
