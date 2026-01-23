role=$1
for policy in `aws iam list-role-policies --role-name $role | jq -r .PolicyNames[]`; do
	aws iam delete-role-policy --role-name $role --policy-name $policy
done
aws iam delete-role --role-name $role 
exit 0
