# modules/vm/variables.tf -- the module's INPUTS (its "function parameters").
#
# Rule of thumb used in this repository:
#   * values that DIFFER per VM (name, size)        -> required, no default
#   * values that are the same for the whole project -> passed in by the caller
#   * sensible technical defaults                    -> default here

variable "instance_name" {
  type        = string
  description = "VM name. Also the prefix of every resource this module creates (<name>-port)."
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

variable "network_name" {
  type        = string
  description = "Name of the project network. List with: openstack network list"
}

variable "external_network_name" {
  type        = string
  description = "External network that floating IPs come from."
  default     = "ext-net"
}

variable "security_groups" {
  type        = list(string)
  description = "NAMES of existing security groups to attach to the VM's port."
}

# The module never reads files itself. Inside a module, `path.module` points at
# the module's own folder, not at the folder of the caller -- so reading the
# caller's users.yaml from here would be fragile. Instead the caller reads the
# file and passes the decoded data in through this variable.
variable "users" {
  description = "Named user accounts to create on the VM (in addition to the default ubuntu user)."
  type = list(object({
    name                = string
    sudo                = optional(bool, false)
    groups              = optional(list(string), [])
    ssh_authorized_keys = optional(list(string), [])
  }))
  default = []
}
