output "private_ssh_key" {
    value       =   tls_private_key.installkey[*].private_key_pem
    sensitive   =   true
}
output "public_ssh_key" {
    value       =   tls_private_key.installkey[*].public_key_openssh
    sensitive   =   true
}