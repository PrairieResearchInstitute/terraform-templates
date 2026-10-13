# vm-c/main.tf -- a ROOT configuration: the folder you run `terraform` in.
#
# Notice how small it is. All the real logic lives in ../modules/vm. What is
# left here is only what is unique to this VM, plus the things a module is not
# allowed to own: the Terraform/provider versions and the provider setup.
#
# Every sibling VM folder is identical except for `instance_name` (and
# optionally the flavor). Each folder has its OWN state file, so you can create,
# change or destroy one VM without Terraform ever looking at the others.

terraform {
  required_version = ">= 1.5"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.0"
    }
  }
}

provider "openstack" {
  cloud = var.os_cloud
}

module "vm" {
  source = "../modules/vm"

  # --- What makes this VM different from the others --------------------------
  instance_name = "vm-c"
  flavor_name   = var.flavor_name

  # --- Values shared by every VM in the project ------------------------------
  key_pair              = var.key_pair
  network_name          = var.network_name
  external_network_name = var.external_network_name
  security_groups       = var.security_groups

  # --- Users: one shared file for all VMs --------------------------------------
  # `file()` reads it, `yamldecode()` turns YAML into Terraform data, `.users`
  # picks the top-level `users:` list. `path.module` is THIS folder, so
  # `../users.yaml` is the file one level up, shared by all the VM folders.
  users = yamldecode(file("${path.module}/../users.yaml")).users
}
