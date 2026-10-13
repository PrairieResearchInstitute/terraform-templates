variable "os_cloud" {
  type        = string
  description = "Name of the entry in clouds.yaml that holds your credentials."
  default     = "my-cloud"
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

variable "vms" {
  description = "One entry per VM that needs a persistent port and floating IP. The map KEY is the VM name and MUST equal instance_name in that VM's folder."
  type = map(object({
    existing_security_groups = list(string)
    extra_ingress_rules = optional(list(object({
      protocol         = string
      port_range_min   = optional(number)
      port_range_max   = optional(number)
      remote_ip_prefix = optional(string, "0.0.0.0/0")
    })), [])
  }))
}
