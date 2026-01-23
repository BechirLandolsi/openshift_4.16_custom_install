
prefix=ocp-skw-hprod-plaasma
for role in `aws iam list-roles | jq -r .Roles[].RoleName | grep "^${prefix}\."`; do
	echo sh delete-role.sh $role
done
