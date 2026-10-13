# network/main.tf -- the persistent network identity of EVERY VM, in ONE state.
#
# Run this folder first (before any VM) and rarely afterwards. It creates, per VM:
# a port (fixed IP), a floating (public) IP and its firewall wiring.
#
# `for_each = var.vms` creates one copy of the module PER KEY of the map. Terraform
# tracks each copy separately (module.network_identity["vm-a"], ["vm-b"], ...).
# That is why you can add "vm-d" to the map later and Terraform will ONLY plan
# new resources for "vm-d": the existing keys are untouched.

terraform {
  required_version = ">= 1.5"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.0"
    }
  }

  # No `backend` block => the default "local" backend: the state is the file
  # ./terraform.tfstate in this folder. Use case 4 replaces this with remote
  # storage so a team (and CI) can share it.
}

provider "openstack" {
  cloud = var.os_cloud
}

module "network_identity" {
  source   = "../modules/network-identity"
  for_each = var.vms

  # The map KEY becomes the VM name. It must match the instance_name used by
  # that VM's folder (vm-a/main.tf), which finds this port as "<key>-port".
  instance_name = each.key

  network_name             = var.network_name
  external_network_name    = var.external_network_name
  existing_security_groups = each.value.existing_security_groups
  extra_ingress_rules      = each.value.extra_ingress_rules
}
