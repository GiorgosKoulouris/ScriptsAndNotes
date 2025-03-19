import pandas as pd
import boto3
import argparse
import datetime


def logActions(level, short_desc, long_desc):
    dt_object = datetime.datetime.now()
    dt_string = dt_object.strftime("%m/%d/%Y %H:%M:%S")
    prefix = f"{dt_string} - {level}:"
    print(f"{prefix} {short_desc}")
    if long_desc:
        print(f"{prefix} {long_desc}")


def init_aws_clients(region):
    try:
        if region == None:
            ec2_client = boto3.client("ec2")
        else:
            ec2_client = boto3.client("ec2", region_name=region)

        logActions("INF", "Successfully created AWS client", None)
        return ec2_client
    except Exception as e:
        logActions("ERR", "Failed to create AWS client", e)
        exit(1)


def read_excel(file_path):
    try:
        df = pd.read_excel(file_path, sheet_name="List")
        logActions("INF", f"Successfully parsed XLS document ({file_path})", None)
        return df
    except Exception as e:
        logActions("ERR", f"Failed to parse XLS document ({file_path})", e)
        exit(1)


def get_vpc_name(vpc_id, ec2_client):
    try:
        """Retrieve the VPC name from its tags."""
        response = ec2_client.describe_vpcs(VpcIds=[vpc_id])
        tags = response["Vpcs"][0].get("Tags", [])
        return next((tag["Value"] for tag in tags if tag["Key"] == "Name"), vpc_id)
    except Exception as e:
        logActions("ERR", f"Failed to get VPC name ({vpc_id})", e)


def get_subnet_name(subnet_id, ec2_client):
    try:
        """Retrieve the Subnet name from its tags."""
        response = ec2_client.describe_subnets(SubnetIds=[subnet_id])
        tags = response["Subnets"][0].get("Tags", [])
        return next((tag["Value"] for tag in tags if tag["Key"] == "Name"), subnet_id)
    except Exception as e:
        logActions("ERR", f"Failed to get Subnet name ({subnet_id})", e)


def get_instance_list(ec2_client):
    try:
        instance_ids = []

        # Describe all instances
        res = ec2_client.describe_instances()

        # Iterate over reservations and instances to get instance IDs
        for reservation in res["Reservations"]:
            for instance in reservation["Instances"]:
                instance_ids.append(instance["InstanceId"])

        return instance_ids

    except Exception as e:
        logActions("ERR", f"Failed to get instance list", e)


def get_instance_info(instance_id, ec2_client):
    """Retrieve EC2 instance details including VPC, subnet, security rules, volume details, and tags."""
    response = ec2_client.describe_instances(InstanceIds=[instance_id])
    instance = response["Reservations"][0]["Instances"][0]

    # Extract basic instance details
    instance_type = instance["InstanceType"]
    platform = instance.get("PlatformDetails", "Uknown")
    tags = instance.get("Tags", [])
    instance_name = next(
        (tag["Value"] for tag in tags if tag["Key"] == "Name"), instance_id
    )

    # Collect tags
    instance_tags = []
    for tag in tags:
        instance_tags.append(
            {
                "InstanceName": instance_name,
                "InstanceID": instance_id,
                "TagKey": tag["Key"],
                "TagValue": tag["Value"],
            }
        )

    # VPC and Subnet details
    vpc_id = instance["VpcId"]
    subnet_id = instance["SubnetId"]
    vpc_name = get_vpc_name(vpc_id, ec2_client)
    subnet_name = get_subnet_name(subnet_id, ec2_client)

    # Collect private IPs from all network interfaces
    private_ips = [
        addr["PrivateIpAddress"]
        for nic in instance["NetworkInterfaces"]
        for addr in nic["PrivateIpAddresses"]
    ]

    # Collect volume details
    volumes = []
    for vol in instance["BlockDeviceMappings"]:
        vol_id = vol["Ebs"]["VolumeId"]
        vol_details = ec2_client.describe_volumes(VolumeIds=[vol_id])["Volumes"][0]
        attachments = vol_details["Attachments"]
        for attachment in attachments:
            if attachment["InstanceId"] == instance_id:
                device_name = attachment["Device"]
        vol_tags = vol_details.get("Tags", [])
        vol_name = next(
            (tag["Value"] for tag in vol_tags if tag["Key"] == "Name"), vol_id
        )
        volumes.append(
            {
                "InstanceName": instance_name,
                "InstanceID": instance_id,
                "VolumeName": vol_name,
                "VolumeId": vol_id,
                "DeviceName": device_name,
                "Type": vol_details["VolumeType"],
                "Size": vol_details["Size"],
                "IOPS": vol_details.get("Iops", "N/A"),
                "Throughput": vol_details.get("Throughput", "N/A"),
                "Encrypted": vol_details["Encrypted"],
                "State": vol_details["State"],
            }
        )

    volumes = sorted(volumes, key=lambda x: x["Size"])

    # Collect security group details
    sg_ids = []
    sg_names = []
    security_rules = []
    for sg in instance["SecurityGroups"]:
        sg_id = sg["GroupId"]
        sg_ids.append(sg_id)

        sg_details = ec2_client.describe_security_groups(GroupIds=[sg_id])[
            "SecurityGroups"
        ][0]
        sg_name = next(
            (
                tag["Value"]
                for tag in sg_details.get("Tags", [])
                if tag["Key"] == "Name"
            ),
            "",
        )
        sg_names.append(sg_name)

        # Process inbound rules
        for rule in sg_details["IpPermissions"]:
            from_port = rule.get("FromPort", "All")
            to_port = rule.get("ToPort", "All")
            protocol = rule.get("IpProtocol", "All")

            for ip_range in rule.get("IpRanges", []):
                rule_description = ip_range.get("Description", " ")
                security_rules.append(
                    {
                        "InstanceName": instance_name,
                        "InstanceID": instance_id,
                        "SecurityGroupName": sg_name,
                        "SecurityGroupID": sg_id,
                        "Direction": "Inbound",
                        "Protocol": protocol,
                        "FromPort": from_port,
                        "ToPort": to_port,
                        "CIDR": ip_range["CidrIp"],
                        "RuleDescription": rule_description,
                    }
                )

            for ip_range in rule.get("Ipv6Ranges", []):
                rule_description = ip_range.get("Description", " ")
                security_rules.append(
                    {
                        "InstanceName": instance_name,
                        "InstanceID": instance_id,
                        "SecurityGroupName": sg_name,
                        "SecurityGroupID": sg_id,
                        "Direction": "Inbound",
                        "Protocol": protocol,
                        "FromPort": from_port,
                        "ToPort": to_port,
                        "CIDR": ip_range["CidrIpv6"],
                        "RuleDescription": rule_description,
                    }
                )

            for prefix_list in rule.get("PrefixListIds", []):
                rule_description = prefix_list.get("Description", " ")
                security_rules.append(
                    {
                        "InstanceName": instance_name,
                        "InstanceID": instance_id,
                        "SecurityGroupName": sg_name,
                        "SecurityGroupID": sg_id,
                        "Direction": "Inbound",
                        "Protocol": protocol,
                        "FromPort": from_port,
                        "ToPort": to_port,
                        "CIDR": prefix_list["PrefixListId"],
                        "RuleDescription": rule_description,
                    }
                )

        # Process outbound rules
        for rule in sg_details["IpPermissionsEgress"]:
            from_port = rule.get("FromPort", "All")
            to_port = rule.get("ToPort", "All")
            protocol = rule.get("IpProtocol", "All")

            for ip_range in rule.get("IpRanges", []):
                rule_description = ip_range.get("Description", " ")
                security_rules.append(
                    {
                        "InstanceName": instance_name,
                        "InstanceID": instance_id,
                        "SecurityGroupName": sg_name,
                        "SecurityGroupID": sg_id,
                        "Direction": "Outbound",
                        "Protocol": protocol,
                        "FromPort": from_port,
                        "ToPort": to_port,
                        "CIDR": ip_range["CidrIp"],
                        "RuleDescription": rule_description,
                    }
                )

            for ip_range in rule.get("Ipv6Ranges", []):
                rule_description = ip_range.get("Description", " ")
                security_rules.append(
                    {
                        "InstanceName": instance_name,
                        "InstanceID": instance_id,
                        "SecurityGroupName": sg_name,
                        "SecurityGroupID": sg_id,
                        "Direction": "Outbound",
                        "Protocol": protocol,
                        "FromPort": from_port,
                        "ToPort": to_port,
                        "CIDR": ip_range["CidrIpv6"],
                        "RuleDescription": rule_description,
                    }
                )

            for prefix_list in rule.get("PrefixListIds", []):
                rule_description = prefix_list.get("Description", " ")
                security_rules.append(
                    {
                        "InstanceName": instance_name,
                        "InstanceID": instance_id,
                        "SecurityGroupName": sg_name,
                        "SecurityGroupID": sg_id,
                        "Direction": "Outbound",
                        "Protocol": protocol,
                        "FromPort": from_port,
                        "ToPort": to_port,
                        "CIDR": prefix_list["PrefixListId"],
                        "RuleDescription": rule_description,
                    }
                )
    instance_info = {
        "InstanceName": instance_name,
        "InstanceID": instance_id,
        "PrivateIPs": ", ".join(private_ips),
        "InstanceType": instance_type,
        "OS": platform,
        "VPC_Name": vpc_name,
        "Subnet_Name": subnet_name,
        "VPC_ID": vpc_id,
        "Subnet_ID": subnet_id,
        "SecurityGroupNames": ", ".join(sg_names),
        "SecurityGroupIDs": ", ".join(sg_ids),
    }
    logActions(
        "INF",
        f"Successfully parsed info for instance {instance_id} ({instance_name})",
        None,
    )
    return instance_info, security_rules, volumes, instance_tags


def get_ec2_details(instance_list, ec2_client):
    instance_data = []
    security_rules_data = []
    volume_data = []
    instance_tags_data = []

    for instance_id in instance_list:
        try:
            instance_info, security_rules, volumes, instance_tags = get_instance_info(
                instance_id, ec2_client
            )
            instance_data.append(instance_info)
            security_rules_data.extend(security_rules)
            volume_data.extend(volumes)
            instance_tags_data.extend(instance_tags)
        except Exception as e:
            logActions("ERR", f"Failed to parse info for instance {instance_id}", e)

    return instance_data, security_rules_data, volume_data, instance_tags_data


def update_workbook(
    instance_data, security_rules_data, volume_data, instance_tags_data, file_path
):
    try:
        # Convert to DataFrames
        instance_df = pd.DataFrame(instance_data)
        security_rules_df = pd.DataFrame(security_rules_data)
        volume_df = pd.DataFrame(volume_data)
        instance_tags_df = pd.DataFrame(instance_tags_data)

        # Save all DataFrames to Excel
        with pd.ExcelWriter(
            file_path, engine="openpyxl", mode="w"
        ) as writer:
            instance_df.to_excel(writer, sheet_name="EC2_Details", index=False)
            security_rules_df.to_excel(writer, sheet_name="EC2_SG_Details", index=False)
            volume_df.to_excel(writer, sheet_name="EC2_Vol_Details", index=False)
            instance_tags_df.to_excel(writer, sheet_name="EC2_Tag_Details", index=False)

        logActions("INF", f"Successfully updated XLS document ({file_path})", None)
    except Exception as e:
        logActions("ERR", f"Failed to update XLS document ({file_path})", e)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()

    parser.add_argument("--region", type=str, required=False, help="Region Name")
    parser.add_argument(
        "--workbook-path", type=str, required=False, help="Path to the XLSX file"
    )
    # Parse the arguments
    args = parser.parse_args()
    region = args.region
    file_path = args.workbook_path

    if file_path == None:
        file_path = "EC2_Details.xlsx"

    ec2_client = init_aws_clients(region)
    instance_list = get_instance_list(ec2_client)
    instance_data, security_rules_data, volume_data, instance_tags_data = (
        get_ec2_details(instance_list, ec2_client)
    )
    update_workbook(
        instance_data, security_rules_data, volume_data, instance_tags_data, file_path
    )
    logActions("INF", f"Execution finished", None)
