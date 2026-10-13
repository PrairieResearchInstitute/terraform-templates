# modules/vm/main.tf -- the reusable "recipe" for ONE VM with a public IP.
#
# This is use case 1's main.tf, moved into a MODULE so that vm-a, vm-b and vm-c
# can all call it instead of each carrying their own copy.
#
# A module is just a folder of .tf files that other configurations call like a
# function: inputs are its `variable`s, outputs are its `output`s.
#
# What a module must NOT contain (the "root" configuration that calls it owns
# these, so one module can be used by many roots):
#   * `provider "openstack" {...}` -- credentials/cloud selection
#   * `backend "..." {...}`        -- where the state is stored
# A module may (and should) declare `required_providers`, so Terraform knows
# which provider the resources inside it belong to. It does not set the version;
# the root does.

terraform {
  required_providers {
    openstack = {
      source = "terraform-provider-openstack/openstack"
    }
  }
}

# --- Lookups by name (identical idea to use case 1) -------------------------
data "openstack_images_image_v2" "base" {
  name        = var.image_name
  most_recent = true
}

data "openstack_compute_flavor_v2" "vm" {
  name = var.flavor_name
}

data "openstack_networking_network_v2" "tenant" {
  name = var.network_name
}

data "openstack_networking_secgroup_v2" "existing" {
  for_each = toset(var.security_groups)
  name     = each.value
}

# --- Networking: port, public IP, association -------------------------------
# Every resource name is derived from `instance_name`, so three VMs created
# from this module never collide ("vm-a-port", "vm-b-port", ...).
resource "openstack_networking_port_v2" "vm" {
  name               = "${var.instance_name}-port"
  network_id         = data.openstack_networking_network_v2.tenant.id
  security_group_ids = [for sg in data.openstack_networking_secgroup_v2.existing : sg.id]
}

resource "openstack_networking_floatingip_v2" "vm" {
  pool = var.external_network_name
}

resource "openstack_networking_floatingip_associate_v2" "vm" {
  floating_ip = openstack_networking_floatingip_v2.vm.address
  port_id     = openstack_networking_port_v2.vm.id
}

# --- The VM ------------------------------------------------------------------
resource "openstack_compute_instance_v2" "vm" {
  name      = var.instance_name
  image_id  = data.openstack_images_image_v2.base.id
  flavor_id = data.openstack_compute_flavor_v2.vm.id
  key_pair  = var.key_pair

  # `local.user_data` is built in cloudinit.tf from the list of users.
  user_data    = local.user_data
  config_drive = true

  network {
    port = openstack_networking_port_v2.vm.id
  }
}
