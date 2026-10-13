output "instance_id" {
  description = "OpenStack ID of the VM."
  value       = openstack_compute_instance_v2.vm.id
}

output "fixed_ip" {
  description = "Private IP address (from the persistent port)."
  value       = data.openstack_networking_port_v2.existing.all_fixed_ips[0]
}

output "floating_ip" {
  description = "Public IP address (from the persistent floating IP)."
  value       = data.openstack_networking_floatingip_v2.existing.address
}

output "provisioned_users" {
  description = "Names of the accounts cloud-init creates at first boot."
  value       = [for u in var.users : u.name]
}
