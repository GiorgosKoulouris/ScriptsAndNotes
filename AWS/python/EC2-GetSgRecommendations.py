import boto3
import ipaddress
import argparse
from prettytable import PrettyTable


def get_instance_vpc(instance_id, ec2_client):
    """Gets the VPC IP of an instance

    :param instance_id: instance ID
    :type instance_id: string
    :param instance_id: EC2 boto client
    :type instance_id: boto client
    :return: VPC ID
    :rtype: string
    """

    instance = ec2_client.describe_instances(InstanceIds=[instance_id])
    vpc_id = instance['Reservations'][0]['Instances'][0]['VpcId']
    return vpc_id


def get_vpc_name(vpc_id, ec2_client):
    """Fetch the VPC name (tag 'Name')."""
    response = ec2_client.describe_vpcs(VpcIds=[vpc_id])
    tags = response['Vpcs'][0].get("Tags", [])

    # Search for the 'Name' tag
    for tag in tags:
        if tag['Key'] == "Name":
            return tag['Value']

    return vpc_id  # Return default if no 'Name' tag is found


def get_instance_security_groups(instance_id, ec2_client):
    """Fetch the security groups attached to the instance."""
    response = ec2_client.describe_instances(InstanceIds=[instance_id])
    security_groups = response['Reservations'][0]['Instances'][0]['SecurityGroups']
    sg_ids = [sg['GroupId'] for sg in security_groups]
    return sg_ids


def get_instance_name(instance_id, ec2_client):
    """Fetch the instance name (tag 'Name') for an instance."""
    response = ec2_client.describe_instances(InstanceIds=[instance_id])
    tags = response['Reservations'][0]['Instances'][0].get("Tags", [])

    # Search for the 'Name' tag
    for tag in tags:
        if tag['Key'] == "Name":
            return tag['Value']

    return instance_id  # Return default if no 'Name' tag is found


def get_sg_name(sg_id, ec2_client):
    """Fetch the Security Group name (tag 'Name')."""
    response = ec2_client.describe_security_groups(GroupIds=[sg_id])
    tags = response['SecurityGroups'][0].get("Tags", [])

    # Search for the 'Name' tag
    for tag in tags:
        if tag['Key'] == "Name":
            return tag['Value']

    return response['SecurityGroups'][0].get(
        "GroupName", ""
    )  # Return default if no 'Name' tag is found


def get_vpc_instances(vpc_id, ec2_client):
    """Fetch all instances in a VPC."""
    response = ec2_client.describe_instances(
        Filters=[{"Name": "vpc-id", "Values": [vpc_id]}]
    )
    instance_ids = [
        instance['InstanceId']
        for reservation in response['Reservations']
        for instance in reservation['Instances']
    ]
    return instance_ids


def get_security_group_rules(sg_ids, ec2_client):
    """Fetch the security group rules for each security group ID."""
    response = ec2_client.describe_security_groups(GroupIds=sg_ids)
    sg_rules = {}
    for sg in response['SecurityGroups']:
        sg_id = sg['GroupId']
        ingress_rules = sg.get("IpPermissions", [])
        for ingress_rule in ingress_rules:
            for ip_range in ingress_rule['IpRanges']:
                ip_range['CanBeDeleted'] = {}
            for pl_id in ingress_rule['PrefixListIds']:
                pl_id['CanBeDeleted'] = {}
        egress_rules = sg.get("IpPermissionsEgress", [])
        for egress_rule in egress_rules:
            for ip_range in egress_rule['IpRanges']:
                ip_range['CanBeDeleted'] = {}
            for pl_id in egress_rule['PrefixListIds']:
                pl_id['CanBeDeleted'] = {}
        sg_rules[sg_id] = {
            "Ingress": ingress_rules,
            "Egress": egress_rules,
            "SgCanBeDetached": {"Ingress": {}, "Egress": {}},
        }
    return sg_rules


def get_prefix_list_cidrs(prefix_list_ids, ec2_client):
    """Fetch CIDR blocks for each prefix list ID."""
    prefix_list_cidrs = {}

    for pl_id in prefix_list_ids:
        try:
            response = ec2_client.get_managed_prefix_list_entries(PrefixListId=pl_id)
            cidrs = [entry['Cidr'] for entry in response.get("Entries", [])]
            prefix_list_cidrs[pl_id] = cidrs
        except Exception as e:
            print(f"Could not fetch prefix list {pl_id}: {e}")
            prefix_list_cidrs[pl_id] = []

    return prefix_list_cidrs


def is_same_protocol_and_ports_included(rule1, rule2):
    """Check if two rules have the same protocol and port range."""
    # If rule2 is ALL/ALL, return True
    if rule2['IpProtocol'] == "-1":
        return True
    # If rule1 is ALL/ALL and rule2 isn't, return False
    if rule1['IpProtocol'] == "-1" and rule2['IpProtocol'] != "-1":
        return False
    # On different protocols, return False
    if rule1['IpProtocol'] != rule2['IpProtocol']:
        return False
    # If rule1 port range is not included in rule2 port range, return False
    if (
        "FromPort" in rule1
        and "FromPort" in rule2
        and "ToPort" in rule1
        and "ToPort" in rule2
    ):
        if rule1['FromPort'] < rule2['FromPort'] or rule1['ToPort'] > rule2['ToPort']:
            return False

    return True


def print_instance_sg_overlaps(instance_id, all_vpc_sg_rules, ec2_client):
    """Analyze security group overlaps including prefix lists and provide recommendations."""

    instance_name = get_instance_name(instance_id, ec2_client)
    instance_sg_ids = get_instance_security_groups(instance_id, ec2_client)
    sg_rules = {}
    for vpc_sg_id, vpc_sg_rule in all_vpc_sg_rules.items():
        if vpc_sg_id in instance_sg_ids:
            sg_rules[vpc_sg_id] = vpc_sg_rule

    recommendations = []

    rule_types = ['Ingress', 'Egress']

    all_prefix_list_ids = set()
    for sg_id, rules in sg_rules.items():
        for rule_type in rule_types:
            rules_of_type = rules.get(rule_type, [])
            for rule in rules_of_type:
                for ip_range in rule.get("IpRanges", []):
                    ip_range['CanBeDeleted'][instance_id] = []
                for pl in rule.get("PrefixListIds", []):
                    pl['CanBeDeleted'][instance_id] = []
                    all_prefix_list_ids.add(pl['PrefixListId'])

    prefix_list_cidrs = get_prefix_list_cidrs(all_prefix_list_ids, ec2_client)

    for sg_id, rules in sg_rules.items():
        sg_name = get_sg_name(sg_id, ec2_client)

        line_items = []
        for rule_type in rule_types:

            rules_of_type = rules.get(rule_type, [])

            for rule in rules_of_type:

                for other_sg_id, other_rules in sg_rules.items():
                    if sg_id == other_sg_id:
                        continue

                    other_rules_of_type = other_rules[rule_type]

                    for other_rule in other_rules_of_type:
                        # CIDR vs CIDR check for overlaps
                        for ip_range in rule.get("IpRanges", []):
                            for other_ip_range in other_rule.get("IpRanges", []):
                                # Only flag overlap if the protocols and ports match
                                if is_same_protocol_and_ports_included(
                                    rule, other_rule
                                ):
                                    if cidrs_are_subnet(
                                        [ip_range['CidrIp']], [other_ip_range['CidrIp']]
                                    ):
                                        other_sg_name = get_sg_name(
                                            other_sg_id, ec2_client
                                        )
                                        line_item = {
                                            "SgName": sg_name,
                                            "SgID": sg_id,
                                            "RuleType": rule_type,
                                            "CIDR": ip_range['CidrIp'],
                                            "Ports": f"{rule['IpProtocol']}/{rule.get('FromPort', 'N/A')}-{rule.get('ToPort', 'N/A')}",
                                            "OtherSG": f"{other_sg_name} ({other_sg_id})",
                                            "OtherCIDR": other_ip_range['CidrIp'],
                                        }
                                        line_items.append(line_item)
                                        ip_range['CanBeDeleted'][instance_id].append(
                                            True
                                        )

                        # CIDR vs Prefix List
                        for ip_range in rule.get("IpRanges", []):
                            for other_pl in other_rule.get("PrefixListIds", []):
                                pl_cidrs = prefix_list_cidrs.get(
                                    other_pl['PrefixListId'], []
                                )
                                # Only flag overlap if the protocols and ports match
                                if is_same_protocol_and_ports_included(
                                    rule, other_rule
                                ):
                                    if cidrs_are_subnet([ip_range['CidrIp']], pl_cidrs):
                                        other_sg_name = get_sg_name(
                                            other_sg_id, ec2_client
                                        )
                                        line_item = {
                                            "SgName": sg_name,
                                            "SgID": sg_id,
                                            "RuleType": rule_type,
                                            "CIDR": ip_range['CidrIp'],
                                            "Ports": f"{rule['IpProtocol']}/{rule.get('FromPort', 'N/A')}-{rule.get('ToPort', 'N/A')}",
                                            "OtherSG": f"{other_sg_name} ({other_sg_id})",
                                            "OtherCIDR": other_pl['PrefixListId'],
                                        }
                                        line_items.append(line_item)
                                        ip_range['CanBeDeleted'][instance_id].append(
                                            True
                                        )

                        # Prefix List vs CIDR
                        for pl in rule.get("PrefixListIds", []):
                            for other_ip_range in other_rule.get("IpRanges", []):
                                pl_cidrs = prefix_list_cidrs.get(pl['PrefixListId'], [])
                                # Only flag overlap if the protocols and ports match
                                if is_same_protocol_and_ports_included(
                                    rule, other_rule
                                ):
                                    if cidrs_are_subnet(
                                        pl_cidrs, [other_ip_range['CidrIp']]
                                    ):
                                        other_sg_name = get_sg_name(
                                            other_sg_id, ec2_client
                                        )
                                        line_item = {
                                            "SgName": sg_name,
                                            "SgID": sg_id,
                                            "RuleType": rule_type,
                                            "CIDR": pl['PrefixListId'],
                                            "Ports": f"{rule['IpProtocol']}/{rule.get('FromPort', 'N/A')}-{rule.get('ToPort', 'N/A')}",
                                            "OtherSG": f"{other_sg_name} ({other_sg_id})",
                                            "OtherCIDR": other_ip_range['CidrIp'],
                                        }
                                        line_items.append(line_item)
                                        pl['CanBeDeleted'][instance_id].append(True)

                        # Prefix List vs Prefix List
                        for pl in rule.get("PrefixListIds", []):
                            for other_pl in other_rule.get("PrefixListIds", []):
                                if is_same_protocol_and_ports_included(
                                    rule, other_rule
                                ):
                                    pl1_cidrs = prefix_list_cidrs.get(
                                        pl['PrefixListId'], []
                                    )
                                    pl2_cidrs = prefix_list_cidrs.get(
                                        other_pl['PrefixListId'], []
                                    )

                                    if cidrs_are_subnet(pl1_cidrs, pl2_cidrs):
                                        other_sg_name = get_sg_name(
                                            other_sg_id, ec2_client
                                        )
                                        line_item = {
                                            "SgName": sg_name,
                                            "SgID": sg_id,
                                            "RuleType": rule_type,
                                            "CIDR": pl['PrefixListId'],
                                            "Ports": f"{rule['IpProtocol']}/{rule.get('FromPort', 'N/A')}-{rule.get('ToPort', 'N/A')}",
                                            "OtherSG": f"{other_sg_name} ({other_sg_id})",
                                            "OtherCIDR": other_pl['PrefixListId'],
                                        }
                                        pl['CanBeDeleted'][instance_id].append(True)
                                        line_items.append(line_item)

                for ip_range in rule['IpRanges']:
                    if True in ip_range['CanBeDeleted'][instance_id]:
                        ip_range['CanBeDeleted'][instance_id] = True
                    else:
                        ip_range['CanBeDeleted'][instance_id] = False
                for pl in rule['PrefixListIds']:
                    if True in pl['CanBeDeleted'][instance_id]:
                        pl['CanBeDeleted'][instance_id] = True
                    else:
                        pl['CanBeDeleted'][instance_id] = False

            # sg_rules[sg_id]['SgCanBeDetached'][rule_type][instance_id] = {}
            can_be_detached_on_type = []
            for rule in rules_of_type:
                for ip_range in rule['IpRanges']:
                    can_be_detached_on_type.append(
                        ip_range['CanBeDeleted'][instance_id]
                    )
                for pl in rule['PrefixListIds']:
                    can_be_detached_on_type.append(pl['CanBeDeleted'][instance_id])
            if not (False in can_be_detached_on_type):
                sg_rules[sg_id]['SgCanBeDetached'][rule_type][instance_id] = True
            else:
                sg_rules[sg_id]['SgCanBeDetached'][rule_type][instance_id] = False

        for line_item in line_items:
            recommendations.append(
                {
                    "InstanceName": instance_name,
                    "InstanceID": instance_id,
                    "SgName": line_item['SgName'],
                    "SgID": line_item['SgID'],
                    "RuleType": line_item['RuleType'],
                    "CIDR": line_item['CIDR'],
                    "Ports": line_item['Ports'],
                    "OtherSG": line_item['OtherSG'],
                    "OtherCIDR": line_item['OtherCIDR'],
                }
            )
    for sg_id, sg_rule in sg_rules.items():
        all_vpc_sg_rules[sg_id] = sg_rule
    return recommendations, all_vpc_sg_rules


def get_all_security_groups_in_vpc(vpc_id):
    """Fetch all security groups in the specified VPC."""
    ec2_client = boto3.client("ec2")
    response = ec2_client.describe_security_groups(
        Filters=[{"Name": "vpc-id", "Values": [vpc_id]}]
    )
    sg_ids = [sg['GroupId'] for sg in response['SecurityGroups']]
    return sg_ids


def get_sg_instances(sg_id):
    """Check if a security group is attached to any instances in the VPC."""
    ec2_client = boto3.client("ec2")
    response = ec2_client.describe_instances(
        Filters=[{"Name": "instance.group-id", "Values": [sg_id]}]
    )
    instance_ids = [
        instance['InstanceId']
        for reservation in response['Reservations']
        for instance in reservation['Instances']
    ]
    return instance_ids


def print_unnattached_sg_recommendation(vpc_id, all_vpc_sg_ids, ec2_client):
    """Analyze security groups in a VPC, checking for unattached security groups."""
    vpc_name = get_vpc_name(vpc_id, ec2_client)
    unattached_sgs = []

    for sg_id in all_vpc_sg_ids:
        # Check if the SG is attached to any instance
        instance_ids = get_sg_instances(sg_id)
        if not instance_ids:
            unattached_sgs.append(sg_id)

    recommendations = []
    # Add recommendations for unattached SGs
    for sg_id in unattached_sgs:
        sg_name = get_sg_name(sg_id, ec2_client)
        recommendations.append([sg_name, sg_id])

    table_headers = ["Security Group Name", "Security Group ID"]
    table = PrettyTable()
    table.title = f"Unattached Security Groups in VPC {vpc_name} ({vpc_id})"
    table.field_names = table_headers
    table.add_rows(recommendations)
    print(table)


def cidrs_are_subnet(cidrs, comp_cidrs):
    all_are_subnet = []
    for cidr in cidrs:
        cidr_is_subnet = []
        net = ipaddress.IPv4Network(cidr)
        for comp_cidr in comp_cidrs:
            comp_net = ipaddress.IPv4Network(comp_cidr)
            cidr_is_subnet.append(net.subnet_of(comp_net))

        if True in cidr_is_subnet:
            all_are_subnet.append(True)
        else:
            all_are_subnet.append(False)

    if False in all_are_subnet:
        return False
    else:
        return True


def find_overlapping_sg_rules_in_sg(vpc_id, ec2_client):
    """Find and print overlapping rules within the same security group in a VPC, including CIDR and prefix list comparisons."""
    vpc_name = get_vpc_name(vpc_id, ec2_client)
    all_sgs_in_vpc = get_all_security_groups_in_vpc(vpc_id)
    sg_rules = get_security_group_rules(all_sgs_in_vpc, ec2_client)

    # Collect all unique prefix list IDs
    all_prefix_list_ids = set()
    for rules in sg_rules.values():
        for rule in rules['Ingress']:
            for pl in rule.get("PrefixListIds", []):
                all_prefix_list_ids.add(pl['PrefixListId'])

    prefix_list_cidrs = get_prefix_list_cidrs(all_prefix_list_ids, ec2_client)
    recommendations = []

    for sg_id, rules in sg_rules.items():
        sg_name = get_sg_name(sg_id, ec2_client)
        ingress_rules = rules['Ingress']
        ingress_rules2 = rules['Ingress']
        # Compare each rule with every other rule in the same security group
        for rule1 in ingress_rules:
            for ip_range1 in rule1.get("IpRanges", []):
                range_can_be_removed = False
                if len(rule1.get("IpRanges", [])) > 1:
                    for ip_range1_2 in rule1.get("IpRanges", []):
                        if (
                            cidrs_are_subnet(
                                [ip_range1['CidrIp']], [ip_range1_2['CidrIp']]
                            )
                            and ip_range1['CidrIp'] != ip_range1_2['CidrIp']
                        ):
                            recommendations.append(
                                [
                                    sg_name,
                                    sg_id,
                                    ip_range1['CidrIp'],
                                    ip_range1_2['CidrIp'],
                                    rule1['IpProtocol'],
                                    f"{rule1.get('FromPort', 'N/A')}-{rule1.get('ToPort', 'N/A')}",
                                    f"Remove rule: {ip_range1['CidrIp']} - {rule1['IpProtocol']}:{rule1.get('FromPort', 'N/A')}-{rule1.get('ToPort', 'N/A')}",
                                ]
                            )
                            range_can_be_removed = True

            for pl1 in rule1.get("PrefixListIds", []):
                pl1_id = pl1['PrefixListId']
                pl1_cidr = prefix_list_cidrs.get(pl1_id, [])
                range_can_be_removed = False
                if len(rule1.get("PrefixListIds", [])) > 1:
                    for pl2 in rule1.get("PrefixListIds", []):
                        pl2_id = pl2['PrefixListId']
                        pl2_cidr = prefix_list_cidrs.get(pl2_id, [])
                        if pl1_id != pl2_id:
                            if (
                                cidrs_are_subnet(pl1_cidr, pl2_cidr)
                                and pl1_id != pl2_id
                            ):
                                recommendations.append(
                                    [
                                        sg_name,
                                        sg_id,
                                        pl1_id,
                                        pl2_id,
                                        rule1['IpProtocol'],
                                        f"{rule1.get('FromPort', 'N/A')}-{rule1.get('ToPort', 'N/A')}",
                                        f"Remove rule: {pl1_id} - {rule1['IpProtocol']}:{rule1.get('FromPort', 'N/A')}-{rule1.get('ToPort', 'N/A')}",
                                    ]
                                )
                            range_can_be_removed = True

                if not range_can_be_removed:
                    for rule2 in ingress_rules2:
                        if not (
                            rule1.get("IpRanges", []) == rule2.get("IpRanges", [])
                            and rule1.get("FromPort", "N/A")
                            == rule2.get("FromPort", "N/A")
                            and rule1.get("ToPort", "N/A") == rule2.get("ToPort", "N/A")
                            and rule1.get("IpProtocol", "N/A")
                            == rule2.get("IpProtocol", "N/A")
                        ):
                            # CIDR vs CIDR: Check for overlap between CIDR blocks
                            for ip_range2 in rule2.get("IpRanges", []):
                                if cidrs_are_subnet(
                                    [ip_range1['CidrIp']], [ip_range2['CidrIp']]
                                ):
                                    if is_same_protocol_and_ports_included(
                                        rule1, rule2
                                    ):
                                        recommendations.append(
                                            [
                                                sg_name,
                                                sg_id,
                                                ip_range1['CidrIp'],
                                                ip_range2['CidrIp'],
                                                rule1['IpProtocol'],
                                                f"{rule1.get('FromPort', 'N/A')}-{rule1.get('ToPort', 'N/A')}",
                                                f"Remove rule: {ip_range1['CidrIp']} - {rule1['IpProtocol']}:{rule1.get('FromPort', 'N/A')}-{rule1.get('ToPort', 'N/A')}",
                                            ]
                                        )

                    # CIDR vs PrefixList: Check if CIDR overlaps with a prefix list
                    for ip_range in rule1.get("IpRanges", []):
                        for prefix_list in rule2.get("PrefixListIds", []):
                            pl_ips = prefix_list_cidrs.get(
                                prefix_list['PrefixListId'], []
                            )
                            if is_same_protocol_and_ports_included(rule1, rule2):
                                if cidrs_are_subnet([ip_range['CidrIp']], pl_ips):
                                    recommendations.append(
                                        [
                                            sg_name,
                                            sg_id,
                                            ip_range['CidrIp'],
                                            f"{prefix_list['PrefixListId']}",
                                            rule1['IpProtocol'],
                                            f"{rule1.get('FromPort', 'N/A')}-{rule1.get('ToPort', 'N/A')}",
                                            f"Remove rule: {ip_range['CidrIp']} - {rule2['IpProtocol']}:{rule2.get('FromPort', 'N/A')}-{rule2.get('ToPort', 'N/A')}",
                                        ]
                                    )

                    # PrefixList vs PrefixList: Check if two prefix lists overlap
                    for prefix_list1 in rule1.get("PrefixListIds", []):
                        pl1_id = prefix_list1['PrefixListId']
                        pl1_cidr = prefix_list_cidrs.get(pl1_id, [])
                        for prefix_list2 in rule2.get("PrefixListIds", []):
                            pl2_id = prefix_list2['PrefixListId']
                            pl2_cidr = prefix_list_cidrs.get(pl2_id, [])
                            if is_same_protocol_and_ports_included(rule1, rule2):
                                if cidrs_are_subnet(pl1_cidr, pl2_cidr) and (
                                    pl1_id != pl2_id
                                ):
                                    recommendations.append(
                                        [
                                            sg_name,
                                            sg_id,
                                            prefix_list1['PrefixListId'],
                                            prefix_list2['PrefixListId'],
                                            rule1['IpProtocol'],
                                            f"{rule1.get('FromPort', 'N/A')}-{rule1.get('ToPort', 'N/A')}",
                                            f"Remove rule: {prefix_list1['PrefixListId']} - {rule2['IpProtocol']}:{rule2.get('FromPort', 'N/A')}-{rule2.get('ToPort', 'N/A')}",
                                        ]
                                    )

                    # PrefixList vs CIDR: Check if a prefix list overlaps with a CIDR block
                    for prefix_list in rule1.get("PrefixListIds", []):
                        pl_id = prefix_list['PrefixListId']
                        pl_cidr = prefix_list_cidrs.get(pl_id, [])
                        for ip_range in rule2.get("IpRanges", []):
                            comp_ip_range = ip_range['CidrIp']
                            if is_same_protocol_and_ports_included(rule1, rule2):
                                if cidrs_are_subnet(pl_cidr, [comp_ip_range]):
                                    recommendations.append(
                                        [
                                            sg_name,
                                            sg_id,
                                            pl_id,
                                            comp_ip_range,
                                            rule1['IpProtocol'],
                                            f"{rule1.get('FromPort', 'N/A')}-{rule1.get('ToPort', 'N/A')}",
                                            f"Remove rule: {pl_id} - {rule1['IpProtocol']}:{rule1.get('FromPort', 'N/A')}-{rule1.get('ToPort', 'N/A')}",
                                        ]
                                    )

    table_headers = [
        "Security Group",
        "Security Group ID",
        "Rule CIDR/Prefix List",
        "Overlapping Rule CIDR/Prefix List",
        "Protocol",
        "Port Range",
        "Recommendation",
    ]
    table = PrettyTable()
    table.title = (
        f"Overlapping Rules within Security Groups in VPC {vpc_name} ({vpc_id})"
    )
    table.field_names = table_headers
    table.add_rows(recommendations)
    print(table)


def update_instance_recommendations(instance_recommendations, vpc_sgs):
    for line in instance_recommendations:
        recomendation_text = ""
        instance_id = line['InstanceID']
        sg_id = line['SgID']
        rule_type = line['RuleType']
        cidr = line['CIDR']
        protocol = line['Ports'].split("/")[0]
        range = line['Ports'].split("/")[1]
        from_port = range.split("-")[0] if range.split("-")[0] != "N/A" else None

        to_port = range.split("-")[1] if range.split("-")[1] != "N/A" else None
        for vpc_sg_id, vpc_sg_rule in vpc_sgs.items():
            if sg_id == vpc_sg_id:
                sg_instances = get_sg_instances(sg_id)
                type_rules = vpc_sg_rule[rule_type]
                for rule in type_rules:
                    rule_proto = rule.get("IpProtocol", None)
                    rule_from_port = rule.get("FromPort", None)
                    rule_to_port = rule.get("ToPort", None)
                    if (
                        str(protocol) == str(rule_proto)
                        and str(from_port) == str(rule_from_port)
                        and str(to_port) == str(rule_to_port)
                    ):
                        if (
                            vpc_sg_rule['SgCanBeDetached']['Ingress'][instance_id]
                            and vpc_sg_rule['SgCanBeDetached']['Egress'][instance_id]
                        ):
                            recomendation_text = f"SG {vpc_sg_id} can be detached"
                        elif vpc_sg_rule['SgCanBeDetached'][rule_type][instance_id]:
                            if rule_type == "Ingress":
                                recomendation_text = f"All SG Ingress rules overlap. SG can't be detached due to Egress rules"
                            else:
                                recomendation_text = f"All SG Egress rules overlap. SG can't be detached due to Ingress rules"
                        else:
                            if cidr.startswith("pl-"):
                                for pl in rule.get("PrefixListIds", []):
                                    if cidr == pl['PrefixListId']:
                                        pl_can_be_deleted_all = []
                                        for i_id, i_can_be_deleted in pl[
                                            "CanBeDeleted"
                                        ].items():
                                            pl_can_be_deleted_all.append(
                                                i_can_be_deleted
                                            )
                                            if i_id == instance_id:
                                                pl_can_be_deleted = i_can_be_deleted
                                        if not (False in pl_can_be_deleted_all):
                                            recomendation_text = f"SG cannot be detached. Rule can be deleted from SG"
                                        else:
                                            recomendation_text = f"SG cannot be detached. Rule cannot be deleted from SG"

                            else:
                                for ip_range in rule.get("IpRanges", []):
                                    print(ip_range)

        line['Recommendation'] = recomendation_text


def main(mode, target, include_instances):
    ec2_client = boto3.client("ec2")
    if mode == "instance":
        instance_id = target
        instance_vpc = get_instance_vpc(instance_id, ec2_client)
        all_vpc_sg_ids = get_all_security_groups_in_vpc(instance_vpc)
        all_vpc_sg_rules = get_security_group_rules(all_vpc_sg_ids, ec2_client)
        recommendations, all_vpc_sg_rules = print_instance_sg_overlaps(
            instance_id, all_vpc_sg_rules, ec2_client
        )

        table_headers = [
            "Name",
            "Instance ID",
            "SG Name",
            "SG ID",
            "Rule Type",
            "Rule CIDR",
            "Ports",
            "Overlapping Security Group",
            "Overlapping CIDR",
        ]
        table = PrettyTable()
        table.title = f"Overlapping SG rules for instances"
        table.field_names = table_headers
        recomendations_table = []
        for row in recommendations:
            recomendations_table.append(
                [
                    row['InstanceName'],
                    row['InstanceID'],
                    row['SgName'],
                    row['SgID'],
                    row['RuleType'],
                    row['CIDR'],
                    row['Ports'],
                    row['OtherSG'],
                    row['OtherCIDR'],
                ]
            )
        table.add_rows(recomendations_table)
        print(table)

    elif mode == "vpc":
        vpc_id = target
        all_vpc_sg_ids = get_all_security_groups_in_vpc(vpc_id)
        all_vpc_sg_rules = get_security_group_rules(all_vpc_sg_ids, ec2_client)

        print_unnattached_sg_recommendation(vpc_id, all_vpc_sg_ids, ec2_client)
        find_overlapping_sg_rules_in_sg(vpc_id, ec2_client)

        if include_instances:
            all_instance_recommendations = []
            instance_ids = get_vpc_instances(target, ec2_client)
            for instance_id in instance_ids:
                instance_recommendations, all_vpc_sg_rules = print_instance_sg_overlaps(
                    instance_id, all_vpc_sg_rules, ec2_client
                )
                all_instance_recommendations += instance_recommendations

            table_headers = [
                "Name",
                "Instance ID",
                "SG Name",
                "SG ID",
                "Rule Type",
                "Rule CIDR",
                "Ports",
                "Overlapping Security Group",
                "Overlapping CIDR",
                "Recommendation",
            ]
            update_instance_recommendations(
                all_instance_recommendations, all_vpc_sg_rules
            )
            table = PrettyTable()
            table.title = f"Overlapping SG rules for instances"
            table.field_names = table_headers
            recomendations_table = []
            for row in all_instance_recommendations:
                recomendations_table.append(
                    [
                        row['InstanceName'],
                        row['InstanceID'],
                        row['SgName'],
                        row['SgID'],
                        row['RuleType'],
                        row['CIDR'],
                        row['Ports'],
                        row['OtherSG'],
                        row['OtherCIDR'],
                        row['Recommendation'],
                    ]
                )
            table.add_rows(recomendations_table)
            table.sortby = "Name"
            print(table)
    else:
        print("Invalid mode. Choose either 'instance' or 'vpc'.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Analyze security group overlaps.")
    parser.add_argument(
        "--mode",
        choices=["instance", "vpc"],
        required=True,
        help="Mode to run: 'instance' or 'vpc'",
    )
    parser.add_argument(
        "--target",
        required=True,
        help="Target ID (instance ID or VPC ID depending on the mode)",
    )
    parser.add_argument(
        "--include-instances",
        required=False,
        action="store_true",
        help="Valid only in vpc mode. When passed, the script will also perform checks against all instances on the VPC",
    )

    args = parser.parse_args()
    main(args.mode, args.target, args.include_instances)
