# storage/terraform.tfvars -- COMMITTED ON PURPOSE in this use case: GitHub Actions reads it,
# so a change here goes through a pull request like any other change.
# Only NON-secret settings belong in this file. Replace every <placeholder> before your first PR.

os_cloud = "my-cloud"

# VM name => size in GB. Keys MUST match the other folders' instance names.
# Check your project quota first:  openstack quota show   (look at gigabytes)
volumes = {
  "vm-a" = 20
  "vm-b" = 20
  "vm-c" = 20
}
