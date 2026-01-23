#!/bin/bash

# Set environment variables for custom installer
export SkipDestroyingSharedTags=On
export IgnoreErrorsOnSharedTags=On

# Run the custom OpenShift installer destroy
./openshift-install destroy cluster --dir=installer-files --log-level=debug