output "instance_id" {
  value = module.vm.instance_id
}

output "provisioned_users" {
  value = module.vm.provisioned_users
}

output "fixed_ip" {
  value = module.vm.fixed_ip
}

# Persistent: this is the same address after every rebuild.
output "floating_ip" {
  value = module.vm.floating_ip
}

output "ssh_command" {
  value = "ssh -i ~/.ssh/<your-private-key>.pem ubuntu@${module.vm.floating_ip}"
}
