#!/bin/bash

# Set environment variables for custom installer
export IgnoreErrorsOnSharedTags=On
export ForceOpenshiftInfraIDRandomPart="${INFRA_RANDOM_ID}"

# Run the custom OpenShift installer
./openshift-install create cluster --dir=installer-files --log-level=debug