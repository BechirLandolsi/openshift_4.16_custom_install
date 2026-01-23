

resource "local_file" "configmap_user_ca_bundle_example" {
  depends_on = [null_resource.openshift_installed]

  content  =  data.template_file.configmap_user_ca_bundle_example.rendered
  filename =  "installer-files/day2/configmap_user_ca_bundle_example.yaml"
}

data "template_file" "configmap_user_ca_bundle_example" {
  template = <<-EOF
apiVersion: v1
data:
  ca-bundle.crt: |
    -----BEGIN CERTIFICATE-----
    MIIDbzCCAlegAwIBAgIIXv77Pj9/5IUwDQYJKoZIhvcNAQELBQAwJjEkMCIGA1UE
    AwwbaW5ncmVzcy1vcGVyYXRvckAxNzA0NzI5MDM3MB4XDTI0MDEwODE1NTAzN1oX
    DTI2MDEwNzE1NTAzOFowJzElMCMGA1UEAwwcKi5hcHBzLmJtMi5yZWRoYXQuaHBl
    Y2ljLm5ldDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKWPT6fiu5VO
    2Yp8U/x2H53hpz9kFMVDtJknddncfaIgDy9qph92c6reHa+anDAuHBJivO9/k572
    xB3PwnvVX9dE+IZ5L+Yn1j5ejs427ikYMObmfFSj/x+bw2IQJ78iuCd+Of6LbJ06
    h1mVEo+cy6ZOnYNIc1OnzEFtqC8CFXuU88mOIqADh/PQNa9d+OtmuyHJpKF+VD7m
    oPqrB2Uq2iJO98Wy0xU0qegaWjGpRdkwVyjny5v6Gd8GB7LCclUPQr4UzikHd+9I
    DqwVJ+V0pGj9nvXyBCC2emrs/x44ikS+MCab7s5Elw27x2ozn8eWYgrK7hSAQrvQ
    5966vUX82ZsCAwEAAaOBnzCBnDAOBgNVHQ8BAf8EBAMCBaAwEwYDVR0lBAwwCgYI
    KwYBBQUHAwEwDAYDVR0TAQH/BAIwADAdBgNVHQ4EFgQUdTFEif5oVcFmMUWzmaFM
    GHLxgrIwHwYDVR0jBBgwFoAUba1g09M8oFgsdq2ioGPebDWtnJ4wJwYDVR0RBCAw
    HoIcKi5hcHBzLmJtMi5yZWRoYXQuaHBlY2ljLm5ldDANBgkqhkiG9w0BAQsFAAOC
    AQEAdS3XVUa+kBa3PMrvVgX7ZCjDgjUuhLqKRTLVWWltMCjTceGxbIF00WDr82/c
    y66KMR7UPdDaFJWRLrjSeGPdoDzPjBn2ZFEbJWgJfezlOsxupKhgeQYwr+LrjhEN
    1CUgWCQsra8TkMmiAMU8SUnPOFFOP3NFe/LuDo2UqDtuAeEolGLRlg7lQfpVFSpH
    oCWJo7EBpKDSh/+9RK4DH7c6ggWs8ErjwVIQogGuGRPDIP9fOPlqnLJDhzG74BVj
    8NkM/QEEuNSDj48g9yMG/TyIKyN2bto9eA7U6Oj2NEUNNHsaTA4uwlc8UivLhImv
    Slck6mvqp3klkZ6pCUAtkpwSHA==
    -----END CERTIFICATE-----
kind: ConfigMap
metadata:
  name: user-ca-bundle-example
  namespace: openshift-config
EOF
}

resource "null_resource" "openshift_day2" {
  depends_on = [null_resource.openshift_installed, local_file.configmap_user_ca_bundle_example]

  provisioner "local-exec" {
    interpreter = ["bash","-c"]
    command     = <<EOT
        KUBECONFIG=installer-files/auth/kubeconfig oc apply -f installer-files/day2 
    EOT
  }
}


# resource "null_resource" "move_ingressController_to_infra_nodes" {
#   depends_on = [null_resource.openshift_day2]
#
#   provisioner "local-exec" {
#     interpreter = ["bash","-c"]
#     command     = <<EOT
#         KUBECONFIG=installer-files/auth/kubeconfig oc patch ingresscontroller/default -n  openshift-ingress-operator  --type=merge -p '{"spec":{"nodePlacement": {"nodeSelector": {"matchLabels": {"node-role.kubernetes.io/infra": ""}},"tolerations": [{"effect":"NoSchedule","key": "node-role.kubernetes.io/infra","value": "reserved"},{"effect":"NoExecute","key": "node-role.kubernetes.io/infra","value": "reserved"}]}}}'
#     EOT
#   }
# }
#
# resource "null_resource" "move_registry_to_infra_nodes" {
#   depends_on = [null_resource.openshift_day2]
#
#   provisioner "local-exec" {
#     interpreter = ["bash","-c"]
#     command     = <<EOT
#         KUBECONFIG=installer-files/auth/kubeconfig oc patch configs.imageregistry.operator.openshift.io/cluster --type=merge -p '{"spec":{"nodeSelector": {"node-role.kubernetes.io/infra": ""},"tolerations": [{"effect":"NoSchedule","key": "node-role.kubernetes.io/infra","value": "reserved"},{"effect":"NoExecute","key": "node-role.kubernetes.io/infra","value": "reserved"}]}}'
#     EOT
#   }
# }

