
prefix=$1
for role in `aws iam list-roles | jq -r .Roles[].RoleName | grep "^${prefix}\-"`; do
	sh delete-role.sh $role
done
