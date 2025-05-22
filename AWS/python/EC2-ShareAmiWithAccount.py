# On the source account/region execute:
# nohup python EC2-ShareAmiWithAccount.py --region currentRegion --ami-id sourceAMI --key-id <kmsID|create> --account-id targetAccountID >> ./ShareAmiWithAccount.log &

import boto3
from botocore.exceptions import ClientError
import argparse
import json


def init_aws_clients(region):
    """Initializes EC2 boto client

    :param region: AWS Region
    :type region: string
    :return: EC2 client
    :rtype: boto_client
    """
    
    try:
        if region:   
            ec2_client = boto3.client("ec2", region_name=region)
            kms_client = boto3.client('kms', region_name=region)
        else:
            ec2_client = boto3.client("ec2")
            kms_client = boto3.client('kms')

        print("Successfully created AWS clients")

        return ec2_client, kms_client
    
    except Exception as e:
        print("Failed to create AWS clients")
        exit(1)

def create_kms_key(kms_client):
    try:
        response = kms_client.create_key(
            Description='PROT-Shared-Key',
            KeyUsage='ENCRYPT_DECRYPT',
            Origin='AWS_KMS'
        )

        key_id = response['KeyMetadata']['KeyId']
        print(f"Succcesfully created KMS with ID: {key_id}")

        key_alias = 'Protera-Shared-Key'
        kms_client.create_alias(
            AliasName=key_alias,
            TargetKeyId=key_id
        )
        print(f"Succcesfully created alias for key: {key_alias}")
        return key_id
    
    except Exception as e:
        print("Failed to create KMS key")
        exit(1)


def share_kms_with_account(key_id, account_id, kms_client):
    try:
        # Get the current key policy
        response = kms_client.get_key_policy(
            KeyId=key_id,
            PolicyName='default'
        )

        # Permissions to grant
        desired_actions = {
            "kms:Encrypt",
            "kms:Decrypt",
            "kms:ReEncrypt*",
            "kms:GenerateDataKey*",
            "kms:DescribeKey"
        }

        current_policy = json.loads(response['Policy'])

        account_arn = f"arn:aws:iam::{account_id}:root"

        # Check if the permission already exists
        statement_exists = False
        for stmt in current_policy.get('Statement', []):
            principals = stmt.get('Principal', {}).get('AWS', [])
            if isinstance(principals, str):
                principals = [principals]

            if account_arn in principals:
                existing_actions = set(stmt.get('Action', []))
                if isinstance(stmt.get('Action'), str):
                    existing_actions = {stmt['Action']}

                if desired_actions.issubset(existing_actions):
                    statement_exists = True
                    break

        # If the statement doesn't exist, append it
        if not statement_exists:
            new_statement = {
                "Sid": "AllowExternalAccountUse",
                "Effect": "Allow",
                "Principal": {
                    "AWS": account_arn
                },
                "Action": sorted(desired_actions),
                "Resource": "*"
            }

            current_policy['Statement'].append(new_statement)

            # Update the key policy
            kms_client.put_key_policy(
                KeyId=key_id,
                Policy=json.dumps(current_policy),
                PolicyName='default'
            )
            print("KMS key policy updated to allow access for account:", account_id)
        else:
            print("KMS key policy already allows access for account:", account_id)

    except Exception as e:
        print("Failed to share KMS key with external account")
        exit(1)

def copy_ami_with_new_encryption(region, ami_id, key_id, ec2_client):  
    try:
        # Describe the existing AMI to get its details
        response = ec2_client.describe_images(ImageIds=[ami_id])
        ami = response['Images'][0]
        
        old_ami_name = ami['Name']
        print(f"Source AMI found: {ami_id} ({old_ami_name})...")
        
        # Define new AMI name
        new_ami_name = f"{old_ami_name}_Shared"
        
        # Initiate the copy of the AMI with a new KMS encryption key
        print(f"Copying AMI '{ami_id}' to a new AMI named {new_ami_name}")
        copy_response = ec2_client.copy_image(
            Name=new_ami_name,
            SourceImageId=ami_id,
            SourceRegion=region,
            Encrypted=True,
            KmsKeyId=key_id
        )
        
        new_ami_id = copy_response['ImageId']
        print(f"Copy initiated. New AMI ID: {new_ami_id}")

        # Wait for the AMI to become available
        print(f"Waiting for the new AMI {new_ami_id} to become available...")
        
        waiter = ec2_client.get_waiter('image_available')
        waiter.wait(
            ImageIds=[new_ami_id],
            WaiterConfig={
                'Delay': 120,
                'MaxAttempts': 120
            }
        )
        print(f"New AMI {new_ami_id} is now available")

    except ClientError as e:
        print(f"Error: {e}")
        return None

    return new_ami_id

def share_ami(ami_id, account_id, ec2_client):
    try:
        ec2_client.modify_image_attribute(
            ImageId=ami_id,
            LaunchPermission={
                'Add': [
                    {'UserId': account_id}
                ]
            }
        )
        print(f"New AMI {ami_id} shared successfully with account {account_id}")

    except Exception as e:
        print(f"Failed to share AMI {ami_id} with external account")
        exit(1)
    
if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--region", type=str, required=True, help="Region Name"
    )
    parser.add_argument(
        "--ami-id", type=str, required=True, help="AMI ID to share"
    )
    parser.add_argument(
        "--key-id", type=str, required=True, help="Encryption key used for sharing"
    )
    parser.add_argument(
        "--account-id", type=str, required=True, help="Account ID to share the AMI with"
    )
    args = parser.parse_args()
    region = args.region
    ami_id = args.ami_id
    key_id = args.key_id
    account_id = args.account_id

    ec2_client, kms_client = init_aws_clients(region)
    
    if key_id == 'create':
        key_id = create_kms_key(kms_client)

    share_kms_with_account(key_id, account_id, kms_client)

    new_ami_id = copy_ami_with_new_encryption(region, ami_id, key_id, ec2_client)

    if new_ami_id:
        share_ami(new_ami_id, account_id, ec2_client)
    else:
        print("Failed to create the new AMI.")

