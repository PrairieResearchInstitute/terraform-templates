output "port_id" {
  description = "ID of the VM's network port."
  value       = openstack_networking_port_v2.vm.id
}

output "fixed_ip" {
  description = "Private IP address on the project network."
  value       = openstack_networking_port_v2.vm.all_fixed_ips[0]
}

output "floating_ip" {
  description = "Public IP address. Persistent: survives any number of VM rebuilds."
  value       = openstack_networking_floatingip_v2.vm.address
}

output "security_group_ids" {
  description = "All security groups attached to the port (existing + extra)."
  value = concat(
    [for sg in data.openstack_networking_secgroup_v2.existing : sg.id],
    [for sg in openstack_networking_secgroup_v2.extra : sg.id]
  )
}
