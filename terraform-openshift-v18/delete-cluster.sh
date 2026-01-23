#!/bin/bash

# Set environment variables for custom installer
export SkipDestroyingSharedTags=On
export IgnoreErrorsOnSharedTags=On

# Check if metadata exists
if [[ ! -f installer-files/metadata.json ]]; then
	echo "⚠ Warning: metadata.json not found"
	echo "The installer will attempt to find resources using cluster name tags"
	echo "Some resources may need manual cleanup"
fi

# Run the custom OpenShift installer destroy
# Note: Installer can still delete resources by searching for cluster tags
# even without metadata.json, though it's less reliable
./openshift-install destroy cluster --dir=installer-files --log-level=debug

EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
	echo "⚠ Installer destroy exited with code: $EXIT_CODE"
	echo "You may need to manually delete remaining resources"
fi

exit $EXIT_CODE