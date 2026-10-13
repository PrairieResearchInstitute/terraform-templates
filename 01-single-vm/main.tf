# main.tf -- everything use case 1 builds: ONE VM reachable from the internet.
#
# You never tell Terraform the ORDER of operations. It reads the references
# between resources (e.g. `port_id = openstack_networking_port_v2.vm.id`) and
# builds a dependency graph:
#
#   lookups ──► port ──► instance
#                 │
#                 └──► floating-IP association ◄── floating IP

# -----------------------------------------------------------------------------
# 1. LOOKUPS (data sources)
#    A `data` block READS something that already exists. It never creates,
#    changes or deletes anything. We look everything up by NAME because names are
#    readable and stay valid when an ID changes (e.g. after an image re-upload).
# -----------------------------------------------------------------------------

# The base operating-system image. `most_recent` picks the newest if several
# images share the name.
data "openstack_images_image_v2" "base" {
  name        = var.image_name
  most_recent = true
}

# The VM size (CPU / RAM / disk).
data "openstack_compute_flavor_v2" "vm" {
  name = var.flavor_name
}

# The private network the VM will live on.
data "openstack_networking_network_v2" "tenant" {
  name = var.network_name
}

# Security groups are firewall rule sets. We ATTACH existing ones (for example
# the shared SSH group your cloud administrators provide) instead of creating
# our own, so this template never opens a port by itself.
# `for_each` creates one lookup per name in the list.
data "openstack_networking_secgroup_v2" "existing" {
  for_each = toset(var.security_groups)
  name     = each.value
}

# -----------------------------------------------------------------------------
# 2. NETWORKING
#    We create the network port ourselves instead of letting the instance
#    create one implicitly. A port is the VM's "network card": it owns the fixed
#    (private) IP and the security groups. Owning it explicitly gives us a
#    stable handle to hang the floating IP on -- and in use case 3 this exact
#    port is what we move into its own state so it survives VM rebuilds.
# -----------------------------------------------------------------------------
resource "openstack_networking_port_v2" "vm" {
  name               = "${var.instance_name}-port"
  network_id         = data.openstack_networking_network_v2.tenant.id
  security_group_ids = [for sg in data.openstack_networking_secgroup_v2.existing : sg.id]
}

# A floating IP is a PUBLIC address taken from the external network's pool.
resource "openstack_networking_floatingip_v2" "vm" {
  pool = var.external_network_name
}

# Glue: attach the public address to the VM's port.
resource "openstack_networking_floatingip_associate_v2" "vm" {
  floating_ip = openstack_networking_floatingip_v2.vm.address
  port_id     = openstack_networking_port_v2.vm.id
}

# -----------------------------------------------------------------------------
# 3. THE VIRTUAL MACHINE
# -----------------------------------------------------------------------------
resource "openstack_compute_instance_v2" "vm" {
  name      = var.instance_name
  image_id  = data.openstack_images_image_v2.base.id
  flavor_id = data.openstack_compute_flavor_v2.vm.id
  key_pair  = var.key_pair

  # cloud-init: a script the VM runs ONCE on first boot (install packages, ...).
  # `file()` reads it from disk; `path.module` is this folder.
  user_data = file("${path.module}/cloud-init.yaml")

  # Radiant (like many OpenStack clouds) delivers user_data through a small
  # virtual CD-ROM called a "config drive". Without this line cloud-init never
  # sees your script and the VM boots "bare".
  config_drive = true

  # Attach the VM to the network THROUGH the port created above.
  network {
    port = openstack_networking_port_v2.vm.id
  }
}
