# vm-b/terraform.tfvars -- COMMITTED ON PURPOSE in this use case: GitHub Actions reads it,
# so a change here goes through a pull request like any other change.
# Only NON-secret settings belong in this file. Replace every <placeholder> before your first PR.
#
# Network, security groups and disk size are NOT set here any more: they live in
# network/ and storage/.

os_cloud = "my-cloud"

# openstack flavor list     (example from Radiant: gp.xlarge)
flavor_name = "<flavor-name>"

# openstack keypair list
key_pair = "<your-keypair-name>"

# OPTIONAL shared network file systems, mounted identically on the VM.
# Leave the list empty if you have none.
nfs_mounts = []
# nfs_mounts = [
#   { source = "nfs.example.org:/export/project-data", target = "/mnt/project-data" },
# ]
