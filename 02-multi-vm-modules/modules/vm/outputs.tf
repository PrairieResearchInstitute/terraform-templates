# modules/vm/outputs.tf -- the module's RETURN VALUES.
# A caller reads them as `module.<name>.<output>` (see vm-a/outputs.tf).

output "instance_id" {
  description = "OpenStack ID of the VM."
  value       = openstack_compute_instance_v2.vm.id
}

output "floating_ip" {
  description = "Public IP address of the VM."
  value       = openstack_networking_floatingip_v2.vm.address
}

output "fixed_ip" {
  description = "Private IP address of the VM on the project network."
  value       = openstack_networking_port_v2.vm.all_fixed_ips[0]
}

output "provisioned_users" {
  description = "Names of the accounts cloud-init creates at first boot."
  value       = [for u in var.users : u.name]
}
