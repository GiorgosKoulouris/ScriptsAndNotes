import boto3
import pandas as pd
import argparse
import json

def get_vpc_mapping(file_path):
    """Reads VPC mapping from an Excel file."""
    df = pd.read_excel(file_path, sheet_name='VPC_Mapping')
    return dict(zip(df['SourceVPC'], df['TargetVPC']))

def get_security_groups(client, vpc_id):
    """Retrieve security groups and their rules for a given VPC."""
    response = client.describe_security_groups(Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}])
    return response.get('SecurityGroups', [])

def get_prefix_lists(client):
    """Retrieve managed prefix lists."""
    response = client.describe_managed_prefix_lists()
    return response.get('PrefixLists', [])

def create_security_group(client, vpc_id, sg_name, description, rules):
    """Create a new security group and apply rules."""
    response = client.create_security_group(VpcId=vpc_id, GroupName=sg_name, Description=description)
    sg_id = response['GroupId']
    client.authorize_security_group_ingress(GroupId=sg_id, IpPermissions=json.loads(rules))
    return sg_id

def extract_account_a_data(file_path, region):
    """Extract security groups and prefix lists from Account A and save to an Excel file."""
    ec2_client = boto3.client('ec2', region_name=region)
    vpc_mapping = get_vpc_mapping(file_path)
    all_sg_data = []
    for source_vpc in vpc_mapping.keys():
        security_groups = get_security_groups(ec2_client, source_vpc)
        for sg in security_groups:
            all_sg_data.append({
                'SourceVPC': source_vpc,
                'SecurityGroupId': sg['GroupId'],
                'SecurityGroupName': sg['GroupName'],
                'Description': sg['Description'],
                'Rules': json.dumps(sg['IpPermissions']),
                'TargetSecurityGroupId': ''  # User will manually fill this
            })

    prefix_lists = get_prefix_lists(ec2_client)
    pl_data = []
    for pl in prefix_lists:
        if pl["OwnerId"] != 'AWS':
            data = {
                'PrefixListId': pl['PrefixListId'], 
                'PrefixListName': pl['PrefixListName']
            }
    prefix_list_data = [{'PrefixListId': pl['PrefixListId'], 'PrefixListName': pl['PrefixListName']} for pl in prefix_lists]

    # Append to existing Excel file
    # with pd.ExcelWriter(file_path, mode='a', if_sheet_exists='replace') as writer:
    #     pd.DataFrame(all_sg_data).to_excel(writer, sheet_name='SecurityGroups', index=False)
    #     pd.DataFrame(prefix_list_data).to_excel(writer, sheet_name='PrefixLists', index=False)
    # print(f"Extracted data saved to {file_path}")

def apply_to_account_b(file_path, dry_run, region):
    """Apply security groups and prefix lists in Account B."""
    ec2_client = boto3.client('ec2', region_name=region)
    vpc_mapping = get_vpc_mapping(file_path)
    df = pd.read_excel(file_path, sheet_name='SecurityGroups')

    for _, row in df.iterrows():
        source_vpc = row['SourceVPC']
        target_vpc = vpc_mapping.get(source_vpc)
        if not target_vpc:
            print(f"Skipping SG {row['SecurityGroupId']} (No target VPC mapping)")
            continue

        sg_id = row['TargetSecurityGroupId']
        if not sg_id:
            print(f"Creating new SG for {row['SecurityGroupName']} in VPC {target_vpc}...")
            if not dry_run:
                sg_id = create_security_group(ec2_client, target_vpc, row['SecurityGroupName'], row['Description'], row['Rules'])
                print(f"Created new SG {sg_id} in VPC {target_vpc}")
            else:
                print(f"Would create new SG {row['SecurityGroupName']} in VPC {target_vpc}")
        else:
            if dry_run:
                print(f"Would update SG {sg_id} in VPC {target_vpc} with rules: {row['Rules']}")
            else:
                print(f"Updating SG {sg_id} in VPC {target_vpc}...")
                ec2_client.authorize_security_group_ingress(
                    GroupId=sg_id,
                    IpPermissions=json.loads(row['Rules'])
                )
                print(f"Updated {sg_id} in VPC {target_vpc}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Replicate AWS Security Groups and Prefix Lists Between Accounts")
    parser.add_argument("--extract", action="store_true", help="Extract SGs and Prefix Lists from Account A")
    parser.add_argument("--apply", action="store_true", help="Apply SGs and Prefix Lists to Account B")
    parser.add_argument("--file", required=True, help="Path to Excel file for mapping and data extraction/application")
    parser.add_argument("--dry-run", action="store_true", help="Log actions without making changes")
    parser.add_argument("--region", required=True, help="AWS region to use")
    args = parser.parse_args()

    if args.extract:
        extract_account_a_data(args.file, args.region)
    elif args.apply:
        apply_to_account_b(args.file, args.dry_run, args.region)
