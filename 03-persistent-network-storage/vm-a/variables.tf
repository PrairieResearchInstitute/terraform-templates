variable "os_cloud" {
  type        = string
  description = "Name of the entry in clouds.yaml that holds your credentials."
  default     = "my-cloud"
}

variable "flavor_name" {
  type        = string
  description = "Flavor (VM size) NAME. List with: openstack flavor list"
}

variable "key_pair" {
  type        = string
  description = "Existing OpenStack key pair for the default (ubuntu) user."
}

variable "nfs_mounts" {
  description = "Optional network file systems to mount: a list of { source, target }."
  type = list(object({
    source = string
    target = string
  }))
  default = []
}
