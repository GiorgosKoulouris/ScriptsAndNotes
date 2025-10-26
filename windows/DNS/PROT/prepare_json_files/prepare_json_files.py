import csv
import json

# Mapping dictionary: Old CSV column names -> New JSON key names
modification_key_mapping = {
    "HostName": "HostName",
    "OldIpAddress": "OldIpAddress",
    "NewIpAddress": "NewIpAddress"
}
resolutionCheck_key_mapping = {
    "HostName": "Hostname",
    "NewIpAddress": "IP"
}

def csv_to_json(csv_file, json_file, key_mapping):
    with open(csv_file, mode='r', encoding='utf-8-sig') as csvf:
        # Create a CSV reader object
        csv_reader = csv.DictReader(csvf)
        
        # Create a list of dictionaries with only mapped keys
        data = []
        for row in csv_reader:
            customized_row = {new_key: row[old_key] for old_key, new_key in key_mapping.items() if old_key in row}
            data.append(customized_row)

        # Write the JSON output
        with open(json_file, mode='w', encoding='utf-8') as jsonf:
            json.dump(data, jsonf, indent=4)

# Example usage
csv_to_json('record_changes.csv', 'dns-entries.json', modification_key_mapping)
csv_to_json('record_changes.csv', 'hostnames_and_ip.json', resolutionCheck_key_mapping)
