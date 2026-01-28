#!/bin/bash
# Delete Route53 DNS record
# Usage: ./delete-record.sh <hosted-zone-id> <record-name>
# Example: ./delete-record.sh Z0247626FGLSOQRQFGDG api.my-cluster.example.com

hostedzone=$1
dns=$2

if [[ -z "$hostedzone" ]] || [[ -z "$dns" ]]; then
    echo "Usage: ./delete-record.sh <hosted-zone-id> <record-name>"
    echo "Example: ./delete-record.sh Z0247626FGLSOQRQFGDG api.my-cluster.example.com"
    exit 1
fi

mkdir -p output

# Ensure dns ends with a dot for Route53 matching
if [[ ! "$dns" == *. ]]; then
    dns="${dns}."
fi

# Convert * to \\052 for Route53 wildcard matching (JSON uses escaped backslash)
dns_route53=$(echo "$dns" | sed 's/\*/\\\\052/g')

echo "Looking for records matching: $dns"
echo "Route53 format: $dns_route53"

# Get all records
aws route53 list-resource-record-sets --hosted-zone-id "$hostedzone" > output/records.json

# Find matching records and build delete batch
# Skip NS and SOA records (required for zone, can't be deleted)
jq --arg dns "$dns_route53" '
[.ResourceRecordSets[] | 
  select(.Name == $dns) |
  select(.Type != "NS" and .Type != "SOA") |
  if .AliasTarget then
    {Action: "DELETE", ResourceRecordSet: {Name: .Name, Type: .Type, AliasTarget: .AliasTarget}}
  elif .ResourceRecords then
    {Action: "DELETE", ResourceRecordSet: {Name: .Name, Type: .Type, TTL: .TTL, ResourceRecords: .ResourceRecords}}
  else
    empty
  end
] | if length > 0 then {Changes: .} else empty end
' output/records.json > output/delete-record.json

# Check if we have records to delete
if [[ ! -s output/delete-record.json ]] || [[ "$(cat output/delete-record.json)" == "" ]]; then
    echo "No deletable records found matching: $dns"
    echo "(NS and SOA records are skipped - they cannot be deleted)"
    echo ""
    echo "Available records in zone:"
    jq -r '.ResourceRecordSets[] | "\(.Type)\t\(.Name)"' output/records.json | head -20
    exit 0
fi

echo "Deleting records:"
jq -r '.Changes[].ResourceRecordSet | "\(.Type) \(.Name)"' output/delete-record.json

# Execute deletion
if aws route53 change-resource-record-sets \
    --hosted-zone-id "$hostedzone" \
    --change-batch file://output/delete-record.json; then
    echo "Record(s) deleted successfully"
else
    echo "Failed to delete records"
    exit 1
fi

exit 0
