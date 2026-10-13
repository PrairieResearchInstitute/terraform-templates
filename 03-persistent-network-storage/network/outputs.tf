output "floating_ips" {
  description = "Public IP of every VM. Persistent."
  value       = { for name, m in module.network_identity : name => m.floating_ip }
}

output "fixed_ips" {
  description = "Private IP of every VM."
  value       = { for name, m in module.network_identity : name => m.fixed_ip }
}

output "port_ids" {
  description = "Port ID of every VM."
  value       = { for name, m in module.network_identity : name => m.port_id }
}

output "security_group_ids" {
  description = "Security groups attached to every VM's port."
  value       = { for name, m in module.network_identity : name => m.security_group_ids }
}
