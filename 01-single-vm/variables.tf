# variables.tf -- every value that differs between people or projects.
#
# A variable WITH a default is optional. A variable WITHOUT a default is
# required: Terraform stops and asks for it if you do not set it in
# terraform.tfvars. Site-specific values (flavor, network, key pair, security
# groups) are deliberately required so you must make a conscious choice.

variable "os_cloud" {
  type        = string
  description = "Name of the entry in clouds.yaml that holds your credentials."
  default     = "my-cloud"
}

variable "instance_name" {
  type        = string
  description = "Name of the VM. Also used to name its network port."
  default     = "my-first-vm"
}

variable "image_name" {
  type        = string
  description = "Glance image NAME (not ID). Looked up by name so re-uploading the image never breaks this code."
  default     = "Ubuntu 24.04"
}

variable "flavor_name" {
  type        = string
  description = "Flavor (VM size) NAME. List the ones you can use with: openstack flavor list"
}

variable "key_pair" {
  type        = string
  description = "Name of an EXISTING OpenStack key pair. Its public half is injected into the VM's default user (ubuntu)."
}

variable "network_name" {
  type        = string
  description = "Name of the project network the VM attaches to. List with: openstack network list"
}

variable "external_network_name" {
  type        = string
  description = "Name of the external (public) network that floating IPs come from. List with: openstack network list --external"
  default     = "ext-net"
}

variable "security_groups" {
  type        = list(string)
  description = "NAMES of existing security groups to attach (they decide which ports are open). List with: openstack security group list"
}
