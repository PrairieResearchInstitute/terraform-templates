# storage/main.tf -- the persistent DATA VOLUMES, one per VM, in ONE state.
#
# A Cinder volume is a network disk that exists independently of any VM. The
# VM folders find these by name ("<vm>-data") and ATTACH them; they never
# create or delete them. So destroying or rebuilding a VM leaves the data alone.

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

resource "openstack_blockstorage_volume_v3" "vm_data" {
  for_each = var.volumes

  # Naming contract: modules/vm looks the volume up as "<instance_name>-data".
  name        = "${each.key}-data"
  size        = each.value
  description = "Persistent data volume for ${each.key}. Survives VM destroy/rebuild; never deleted by routine automation."

  # Lets you GROW the volume while it is attached to a running VM. (Shrinking is
  # never possible.) After growing it you must also grow the filesystem inside
  # the VM -- see the README.
  enable_online_resize = true

  # Safety net: any plan that would delete a volume fails with an error. To
  # really remove a volume, delete this block deliberately first (README, "Tear
  # everything down").
  lifecycle {
    prevent_destroy = true
  }
}
