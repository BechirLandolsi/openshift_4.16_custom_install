hostedzone=$1
dns=$2

mkdir -p output
aws route53 list-resource-record-sets --hosted-zone-id $hostedzone > output/records.json
jq --compact-output '[.ResourceRecordSets[] |
   select(.Name == "'$dns'.") |
   {Action: "DELETE", ResourceRecordSet: {Name: .Name, Type: .Type, AliasTarget: .AliasTarget}}] |
   _nwise(1) |
   {Changes: .}' output/records.json > output/delete-record.json
aws route53 change-resource-record-sets --hosted-zone-id $hostedzone --change-batch=file://./output/delete-record.json 
exit 0

