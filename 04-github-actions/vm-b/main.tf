# vm-b/main.tf -- ROOT for one VM. Compare with use case 2: no network settings
# are passed any more. The port, floating IP and volume already exist (created
# by network/ and storage/); the module finds them by the name "vm-b".
#
# Apply order for a brand-new project:  network/  ->  storage/  ->  vm-*/
#
# Every sibling VM folder is identical except for `instance_name` (and
# optionally the flavor). Each has its OWN state file.

terraform {
  required_version = ">= 1.10"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.0"
    }
  }

  # Remote state, partial configuration: see vm-a/main.tf for the explanation.
  backend "s3" {
    key = "vm-b/terraform.tfstate"
  }
}

provider "openstack" {
  cloud = var.os_cloud
}

module "vm" {
  source = "../modules/vm"

  # --- What makes this VM different from the others --------------------------
  # The name MUST be a key of `vms` in network/ and of `volumes` in storage/.
  instance_name = "vm-b"
  flavor_name   = var.flavor_name

  key_pair = var.key_pair

  # One shared, COMMITTED users file for all VMs (see ../users.yaml). Editing it by pull request is how people are added.
  users = yamldecode(file("${path.module}/../users.yaml")).users

  # Optional shared network file systems (empty list = none).
  nfs_mounts = var.nfs_mounts
}
