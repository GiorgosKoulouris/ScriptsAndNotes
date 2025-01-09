import boto3
from botocore.exceptions import ClientError

def copy_ami_with_new_encryption(region, ami_id, new_encryption_key, account_id):
    # Create an EC2 client in the specified region
    ec2_client = boto3.client('ec2', region_name=region)
    
    try:
        # Describe the existing AMI to get its details
        response = ec2_client.describe_images(ImageIds=[ami_id])
        ami = response['Images'][0]
        
        old_ami_name = ami['Name']
        print(f"Found AMI: {old_ami_name}")
        
        # Define new AMI name
        new_ami_name = f"{old_ami_name}_Shared"
        
        # Initiate the copy of the AMI with a new KMS encryption key
        print(f"Copying AMI '{ami_id}' to a new AMI with the name '{new_ami_name}'")
        copy_response = ec2_client.copy_image(
            Name=new_ami_name,
            SourceImageId=ami_id,
            SourceRegion=region,
            Encrypted=True,
            KmsKeyId=new_encryption_key
        )
        
        new_ami_id = copy_response['ImageId']
        print(f"Copy initiated. New AMI ID: {new_ami_id}")

        # Wait for the AMI to become available
        print(f"Waiting for the new AMI {new_ami_id} to become available...")
        waiter = ec2_client.get_waiter('image_available')
        waiter.wait(ImageIds=[new_ami_id])
        print(f"New AMI {new_ami_id} is now available")

        # Share the new AMI with the provided AWS account ID
        print(f"Sharing the new AMI with account ID: {account_id}")
        ec2_client.modify_image_attribute(
            ImageId=new_ami_id,
            LaunchPermission={
                'Add': [
                    {'UserId': account_id}
                ]
            }
        )
        print(f"New AMI {new_ami_id} shared successfully with account {account_id}")

    except ClientError as e:
        print(f"Error: {e}")
        return None

    return new_ami_id

if __name__ == "__main__":
    # User input
    region = input("Enter AWS region: ")
    ami_id = input("Enter the AMI ID to copy: ")
    new_encryption_key = input("Enter the new KMS Encryption Key ID: ")
    account_id = input("Enter the AWS Account ID to share the new AMI with: ")

    # Call the function to copy the AMI and share it
    new_ami_id = copy_ami_with_new_encryption(region, ami_id, new_encryption_key, account_id)
    if new_ami_id:
        print(f"Successfully created and shared new AMI: {new_ami_id}")
    else:
        print("Failed to create or share the new AMI.")
