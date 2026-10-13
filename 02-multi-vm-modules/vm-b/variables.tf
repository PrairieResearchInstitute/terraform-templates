# vm-b/variables.tf -- inputs of this ROOT. Values come from terraform.tfvars.
# (The module has its own, separate variables: values must be passed down
# explicitly in the `module` block. Nothing is inherited automatically.)

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
  description = "NAMES of existing security groups to attach. Must include one that allows SSH."
}
