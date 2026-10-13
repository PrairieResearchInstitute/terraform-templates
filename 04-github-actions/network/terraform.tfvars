# network/terraform.tfvars -- COMMITTED ON PURPOSE in this use case: GitHub Actions reads it,
# so a change here goes through a pull request like any other change.
# Only NON-secret settings belong in this file. Replace every <placeholder> before your first PR.
#   export OS_CLOUD=my-cloud   # so the `openstack ... list` commands below work

os_cloud = "my-cloud"

# openstack network list
network_name = "<your-project-network>"

# openstack network list --external
external_network_name = "ext-net"

# One entry per VM. The KEY ("vm-a") is the VM's name everywhere else.
# openstack security group list   (one of them must allow SSH)
vms = {
  "vm-a" = {
    existing_security_groups = ["default", "<your-ssh-security-group>"]
  }

  "vm-b" = {
    existing_security_groups = ["default", "<your-ssh-security-group>"]
  }

  "vm-c" = {
    existing_security_groups = ["default", "<your-ssh-security-group>"]

    # OPTIONAL: extra rules the shared groups do not cover. This one opens
    # TCP 8080, but only to the 203.0.113.0/24 range (omit remote_ip_prefix to
    # open it to the whole internet -- think twice).
    # extra_ingress_rules = [
    #   { protocol = "tcp", port_range_min = 8080, port_range_max = 8080, remote_ip_prefix = "203.0.113.0/24" },
    # ]
  }
}
