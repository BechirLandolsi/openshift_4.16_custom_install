package installconfig

import (
	"crypto/rand"
	"fmt"
	"os"
	"strings"

	"github.com/openshift/installer/pkg/asset"
	utilrand "k8s.io/apimachinery/pkg/util/rand"
)

const (
	// randomLen is the length of the random string appended to the infrastructure name.
	randomLen = 5
)

// ClusterID is the unique ID of the cluster, immutable during the cluster's life.
type ClusterID struct {
	// UUID is a globally unique identifier.
	UUID string

	// InfraID is an identifier for the cluster that is unique within the AWS account.
	InfraID string
}

var _ asset.Asset = (*ClusterID)(nil)

// Dependencies returns the install-config asset as a dependency.
func (a *ClusterID) Dependencies() []asset.Asset {
	return []asset.Asset{
		&InstallConfig{},
	}
}

// Generate generates the ClusterID.
func (a *ClusterID) Generate(dependencies asset.Parents) error {
	ic := &InstallConfig{}
	dependencies.Get(ic)

	// Generate a random UUID for the cluster
	uuid, err := generateUUID()
	if err != nil {
		return err
	}
	a.UUID = uuid

	// Generate InfraID from cluster name
	a.InfraID = generateInfraID(ic.Config.ObjectMeta.Name)

	return nil
}

// Name returns the human-friendly name of the asset.
func (a *ClusterID) Name() string {
	return "Cluster ID"
}

// generateUUID generates a random UUID.
func generateUUID() (string, error) {
	var uuid [16]byte
	if _, err := rand.Read(uuid[:]); err != nil {
		return "", err
	}
	uuid[6] = (uuid[6] & 0x0f) | 0x40 // Version 4
	uuid[8] = (uuid[8] & 0x3f) | 0x80 // Variant 10
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x",
		uuid[0:4], uuid[4:6], uuid[6:8], uuid[8:10], uuid[10:16]), nil
}

// generateInfraID generates an InfraID from the cluster name.
func generateInfraID(base string) string {
	maxBaseLen := 27 - (randomLen + 1)
	if len(base) > maxBaseLen {
		base = base[:maxBaseLen]
	}
	base = strings.TrimRight(base, "-")
	
	rand := os.Getenv("ForceOpenshiftInfraIDRandomPart")
	if rand == "" {
		rand = utilrand.String(randomLen)
	}
	return fmt.Sprintf("%s-%s", base, rand)
}
