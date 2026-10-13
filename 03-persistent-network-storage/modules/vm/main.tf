# modules/vm/main.tf -- the EPHEMERAL part: the compute instance and the glue to
# its persistent neighbours.
#
# Compared with use case 2 this module creates NO networking and NO storage.
# It LOOKS THEM UP BY NAME, using the naming contract:
#
#     port   "<instance_name>-port"   created by network/
#     volume "<instance_name>-data"   created by storage/
#
# Consequence: `terraform destroy` in a VM folder can only ever remove the
# instance and the volume ATTACHMENT. The addresses and the data stay.

terraform {
  required_providers {
    openstack = {
      source = "terraform-provider-openstack/openstack"
    }
  }
}

data "openstack_images_image_v2" "base" {
  name        = var.image_name
  most_recent = true
}

data "openstack_compute_flavor_v2" "vm" {
  name = var.flavor_name
}

# Created earlier by network/. If this lookup fails, you have not applied
# network/ yet (or the VM name does not match the key used there).
data "openstack_networking_port_v2" "existing" {
  name = "${var.instance_name}-port"
}

# Created earlier by storage/. Same advice if this fails.
data "openstack_blockstorage_volume_v3" "data" {
  name = "${var.instance_name}-data"
}

# The floating IP is found through the port it is attached to. Reading it live
# from OpenStack means this folder needs no access to the network/ state file.
data "openstack_networking_floatingip_v2" "existing" {
  port_id = data.openstack_networking_port_v2.existing.id
}

resource "openstack_compute_instance_v2" "vm" {
  name      = var.instance_name
  image_id  = data.openstack_images_image_v2.base.id
  flavor_id = data.openstack_compute_flavor_v2.vm.id
  key_pair  = var.key_pair

  user_data    = local.user_data
  config_drive = true

  network {
    port = data.openstack_networking_port_v2.existing.id
  }

  lifecycle {
    # `image_id` is looked up by name, so re-uploading the Ubuntu image changes
    # it. Without this line Terraform would plan to REPLACE every VM just
    # because a newer base image exists. With it, VMs keep the image they were
    # built from until you rebuild them on purpose:
    #   terraform apply -replace=module.vm.openstack_compute_instance_v2.vm
    ignore_changes = [image_id]
  }
}

# Attach the persistent volume. This attachment is created and destroyed with
# the instance; the volume itself (owned by storage/) is untouched either way.
resource "openstack_compute_volume_attach_v2" "data" {
  instance_id = openstack_compute_instance_v2.vm.id
  volume_id   = data.openstack_blockstorage_volume_v3.data.id
}
