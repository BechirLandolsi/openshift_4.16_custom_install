#fetch the terraform states and the kubeconfig on the aws s3 bucket
#and use openshift-installer to destroy all objects created on aws for the cluster (using tags owned)
#and deletes dns records and roles that are not deleted by the openshift-installer


hostedzone=$1
cluster=$2
domain=$3
bucket=$4

if [[ ! -f installer-files/auth/kubeconfig ]]; then
	echo "Kubeconfig not found locally. Attempting to fetch from S3..."
	if aws s3 cp s3://$bucket/installer-files.tar installer-files.tar 2>/dev/null; then
		echo "✓ Files fetched from S3"
		tar xvf installer-files.tar
	else
		echo "⚠ Warning: Could not fetch from S3 (bucket may not exist)"
		echo "Continuing with manual destroy using cluster tags..."
	fi
fi

# Run OpenShift installer destroy
# Even without metadata.json, installer can find resources by tags
timeout -k 30m 25m sh delete-cluster.sh 
sh delete-record.sh $hostedzone api.$cluster.$domain
sh delete-record.sh $hostedzone api-int.$cluster.$domain
sh delete-roles.sh $cluster
