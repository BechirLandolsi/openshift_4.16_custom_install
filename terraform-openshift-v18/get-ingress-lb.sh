#!/usr/bin/env bash
# waits for ingress hostname being available
# fetch the ingress hostname
# find the aws load balancer with this DNSName
# output the LoadBalancerArn json for the aws load balancer

set -euxo pipefail

eval "$(jq -r '@sh "bucket=\(.bucket)"')"

OUTPUTDIR=.
ERRORFILE="$OUTPUTDIR/get_ingress_error.log"
STDFILE="$OUTPUTDIR/get_ingress_exec.log"

{
    if [[ ! -f installer-files/auth/kubeconfig ]]; then
        aws s3 cp s3://$bucket/installer-files.tar installer-files.tar
        tar xvf installer-files.tar
    fi

    sh wait.sh 2 20 "$ERRORFILE" "KUBECONFIG=installer-files/auth/kubeconfig oc -n openshift-ingress get service router-default -o json 2>&1 | jq -e '.status.loadBalancer.ingress[0].hostname'"
    hostname=`KUBECONFIG=installer-files/auth/kubeconfig oc -n openshift-ingress get service router-default -o json | jq -r .status.loadBalancer.ingress[0].hostname`
    echo "Extracted hostname: $hostname"
    aws elb describe-load-balancers --output json > elb_output.json
    cat elb_output.json
    lbarn=$(jq -r --arg dnsname "$hostname" '.LoadBalancers[] | select(.DNSName == $dnsname) | .LoadBalancerArn' elb_output.json)
    echo "Extracted LoadBalancerArn: $lbarn"
} >"$STDFILE" 2>>"$ERRORFILE"

jq -n --arg lbarn "$lbarn" '{"LoadBalancerArn":$lbarn}'


