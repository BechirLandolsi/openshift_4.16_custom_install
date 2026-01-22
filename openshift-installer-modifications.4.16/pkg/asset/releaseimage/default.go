package releaseimage

// Default returns the default OpenShift release image for new installations
// Modified to use OpenShift 4.16.9 from official Red Hat registry
func Default() (string, error) {
	return "quay.io/openshift-release-dev/ocp-release:4.16.9-x86_64", nil
}
