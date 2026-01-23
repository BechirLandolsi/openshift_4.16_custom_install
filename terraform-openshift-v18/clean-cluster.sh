#fetch the terraform states and the kubeconfig on the aws s3 bucket
#and use openshift-installer to destroy all objects created on aws for the cluster (using tags owned)
#and deletes dns records and roles that are not deleted by the openshift-installer


hostedzone=$1
cluster=$2
domain=$3
bucket=$4

if [[ ! -f installer-files/auth/kubeconfig ]]; then
	aws s3 cp s3://$bucket/installer-files.tar installer-files.tar
	tar xvf installer-files.tar
fi

timeout -k 15m 10m sh delete-cluster.sh 
sh delete-record.sh $hostedzone api.$cluster.$domain
sh delete-record.sh $hostedzone api-int.$cluster.$domain
sh delete-roles.sh $cluster
