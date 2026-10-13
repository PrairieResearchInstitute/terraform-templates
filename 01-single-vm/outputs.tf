# outputs.tf -- values Terraform prints after `apply` (and on `terraform output`).
# Outputs are how a configuration "returns" information to the human running it.

output "instance_id" {
  description = "OpenStack ID of the VM."
  value       = openstack_compute_instance_v2.vm.id
}

output "floating_ip" {
  description = "Public IP address of the VM."
  value       = openstack_networking_floatingip_v2.vm.address
}

# A ready-to-paste login command. `ubuntu` is the default user on Ubuntu cloud
# images; replace the key path with the private key that matches `key_pair`.
output "ssh_command" {
  description = "Command to log in to the VM."
  value       = "ssh -i ~/.ssh/<your-private-key>.pem ubuntu@${openstack_networking_floatingip_v2.vm.address}"
}
