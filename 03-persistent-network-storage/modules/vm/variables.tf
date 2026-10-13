variable "instance_name" {
  type        = string
  description = "VM name. MUST match the key used for this VM in network/ and storage/, because the port and volume are looked up as '<instance_name>-port' and '<instance_name>-data'."
}

variable "image_name" {
  type        = string
  description = "Glance image NAME, resolved to an ID by a data source."
  default     = "Ubuntu 24.04"
}

variable "flavor_name" {
  type        = string
  description = "Flavor (VM size) NAME. List with: openstack flavor list"
}

variable "key_pair" {
  type        = string
  description = "Existing OpenStack key pair for the default (ubuntu) user."
}

variable "data_device" {
  type        = string
  description = "Device name the persistent volume appears as inside the VM. /dev/vdb is typical on OpenStack with KVM. Verify on the first boot with: lsblk"
  default     = "/dev/vdb"
}

variable "data_mount_point" {
  type        = string
  description = "Directory where the persistent volume is mounted inside the VM."
  default     = "/data"
}

variable "nfs_mounts" {
  description = "Optional network file systems to mount (for example institutional shared storage). Each entry becomes an /etc/fstab line."
  type = list(object({
    source = string
    target = string
  }))
  default = []
}

# From this use case on, accounts carry NUMERIC ids (uid/gid). Files on a
# persistent volume or a shared file system are owned by NUMBERS, not names. If a
# rebuilt VM gave 'alice' a different uid, she would no longer own her own files.
variable "users" {
  description = "Named accounts to create on the VM, with fixed numeric ids."
  type = list(object({
    name = string
    uid  = number
    primary_group = object({
      name = string
      gid  = number
    })
    groups = optional(list(object({
      name = string
      gid  = number
    })), [])
    sudo                = optional(bool, false)
    ssh_authorized_keys = optional(list(string), [])
  }))
  default = []
}
