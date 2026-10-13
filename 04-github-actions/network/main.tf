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
  required_version = ">= 1.10"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.0"
    }
  }

  # REMOTE STATE (new in use case 4). The state file lives in an S3-compatible
  # bucket instead of on one laptop, so your team AND the CI runner read and
  # write the same state, and the bucket holds a lock while someone applies.
  #
  # This is a PARTIAL configuration: only the part that is unique to this
  # folder (the object name, `key`) is written here. Everything shared comes
  # from ../backend.hcl, and the secrets (bucket name, endpoint, access keys)
  # come from environment variables. Nothing sensitive is committed.
  # Initialise with the command in the README ("terraform init -backend-config=...").
  backend "s3" {
    key = "network/terraform.tfstate"
  }
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
