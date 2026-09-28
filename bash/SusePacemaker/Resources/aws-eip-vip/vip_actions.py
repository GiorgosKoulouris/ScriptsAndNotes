import requests
import boto3
import time
import argparse

# Metadata service URL
TOKEN_URL = "http://169.254.169.254/latest/api/token"
METADATA_URL = "http://169.254.169.254/latest/meta-data"

# Parse command-line arguments
parser = argparse.ArgumentParser(description="Detach an ENI and attach it to another instance.")
parser.add_argument("--eni-id", required=True, help="Elastic Network Interface (ENI) ID")
parser.add_argument("--action", required=True, help="Action to perform (attach|detach)")

# Assign parsed arguments
args = parser.parse_args()
eni_id = args.eni_id
action = args.action

# Function to get IMDSv2 token
def get_imds_token():
    headers = {"X-aws-ec2-metadata-token-ttl-seconds": "120"}  # 2-minute token
    response = requests.put(TOKEN_URL, headers=headers)
    response.raise_for_status()
    return response.text

# Function to get metadata with token
def get_metadata(path, token):
    headers = {"X-aws-ec2-metadata-token": token}
    response = requests.get(f"{METADATA_URL}/{path}", headers=headers)
    response.raise_for_status()
    return response.text

# Get token
token = get_imds_token()

# Get region
region = get_metadata("placement/region", token)

# Boto3 client
ec2 = boto3.client("ec2", region_name=region)

if action != 'monitor':
    # Describe ENI
    eni_info = ec2.describe_network_interfaces(NetworkInterfaceIds=[eni_id])["NetworkInterfaces"][0]
    if "Attachment" in eni_info:
        # Detach network interface
        print(f"Detaching ENI {eni_id}...")
        attachment_id = eni_info["Attachment"]["AttachmentId"]

        ec2.detach_network_interface(AttachmentId=attachment_id, Force=True)

        # Wait for detachment by polling the ENI status
        print(f"Waiting for ENI {eni_id} to be fully detached...")
        while True:
            time.sleep(5)  # Polling interval
            eni_status = ec2.describe_network_interfaces(NetworkInterfaceIds=[eni_id])["NetworkInterfaces"][0]["Status"]
            
            if eni_status == "available":
                print(f"ENI {eni_id} is now available.")
                break
            else:
                print(f"ENI {eni_id} is still {eni_status}. Retrying...")
    else:
        print(f"ENI {eni_id} is already available.")
        
    if action == 'attach':
        instance_id = get_metadata("instance-id", token)
        # Attach to new instance
        print(f"Attaching ENI {eni_id} to {instance_id}...")
        ec2.attach_network_interface(NetworkInterfaceId=eni_id, InstanceId=instance_id, DeviceIndex=1)

        while True:
            time.sleep(5)  # Polling interval
            eni_status = ec2.describe_network_interfaces(NetworkInterfaceIds=[eni_id])["NetworkInterfaces"][0]["Status"]
            
            if eni_status == "available":
                print(f"ENI {eni_id} is still {eni_status}. Retrying...")
            else:
                print("Network Interface successfully moved!")
                break
        
if action == 'monitor':
    instance_id = get_metadata("instance-id", token)
    eni_info = ec2.describe_network_interfaces(NetworkInterfaceIds=[eni_id])["NetworkInterfaces"][0]
    if "Attachment" in eni_info:
        attached_instance_id = eni_info["Attachment"]["InstanceId"]
        
        if instance_id == attached_instance_id:
            print(f"Configuration OK. VIP is attached to {instance_id}")
            exit(0)
        else:
            print(f"Misconfiguration found. VIP is attached to {attached_instance_id} while running instance is {instance_id}")
            exit(1)
            
    else:
        print(f"ENI {eni_id} is not attached to any instance.")
        exit(1)