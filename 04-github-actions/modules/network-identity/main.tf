# modules/network-identity/main.tf -- the PERSISTENT half of a VM's identity:
#
#   firewall rules  +  network port (fixed private IP)  +  floating (public) IP
#
# This module is applied from the `network/` folder, with its own state. Nothing
# in `modules/vm` can create or destroy these resources, so rebuilding a VM keeps
# its addresses. They are tied back to the VM later only by NAME
# (`<instance_name>-port`).

terraform {
  required_providers {
    openstack = {
      source = "terraform-provider-openstack/openstack"
    }
  }
}

data "openstack_networking_network_v2" "tenant" {
  name = var.network_name
}

# Firewall rule sets that already exist in the project (for example the shared
# SSH group provided by your cloud administrators). Attached, never modified.
data "openstack_networking_secgroup_v2" "existing" {
  for_each = toset(var.existing_security_groups)
  name     = each.value
}

# A small, VM-specific group, created ONLY when extra rules are requested.
# `count = 0` or `1` is the usual idiom for "create this resource optionally".
resource "openstack_networking_secgroup_v2" "extra" {
  count       = length(var.extra_ingress_rules) > 0 ? 1 : 0
  name        = "${var.instance_name}-extra-sg"
  description = "Rules for ${var.instance_name} not covered by the shared security groups"
}

# One rule per entry. Keying by list position keeps the Terraform addresses
# stable as long as you only append rules.
resource "openstack_networking_secgroup_rule_v2" "extra_ingress" {
  for_each = { for idx, rule in var.extra_ingress_rules : idx => rule }

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = each.value.protocol
  port_range_min    = each.value.port_range_min
  port_range_max    = each.value.port_range_max
  remote_ip_prefix  = each.value.remote_ip_prefix
  security_group_id = openstack_networking_secgroup_v2.extra[0].id
}

# The port is the VM's network card. The VM (modules/vm) finds it by name.
resource "openstack_networking_port_v2" "vm" {
  name       = "${var.instance_name}-port"
  network_id = data.openstack_networking_network_v2.tenant.id
  security_group_ids = concat(
    [for sg in data.openstack_networking_secgroup_v2.existing : sg.id],
    [for sg in openstack_networking_secgroup_v2.extra : sg.id]
  )
}

# The public address. Losing this one means DNS records, allow-lists and
# bookmarks stop working, so Terraform is told to refuse to destroy it.
resource "openstack_networking_floatingip_v2" "vm" {
  pool = var.external_network_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "openstack_networking_floatingip_associate_v2" "vm" {
  floating_ip = openstack_networking_floatingip_v2.vm.address
  port_id     = openstack_networking_port_v2.vm.id
}
