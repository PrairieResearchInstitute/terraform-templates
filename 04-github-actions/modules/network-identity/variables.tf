variable "instance_name" {
  type        = string
  description = "VM name. Derives the resource names (<name>-port, <name>-extra-sg). MUST equal the instance_name the VM folder passes to modules/vm, because the VM finds its port by this name."
}

variable "network_name" {
  type        = string
  description = "Name of the project network the port is created on."
}

variable "external_network_name" {
  type        = string
  description = "External network that floating IPs come from."
  default     = "ext-net"
}

variable "existing_security_groups" {
  type        = list(string)
  description = "NAMES of security groups that already exist in the project (for example \"default\" and your shared SSH group). Looked up, never created or modified here."
  default     = []
}

variable "extra_ingress_rules" {
  description = "Extra inbound rules that the existing groups do not cover. Creates a small group named <instance_name>-extra-sg. By default a rule is open to the whole internet; set remote_ip_prefix to restrict it."
  type = list(object({
    protocol         = string
    port_range_min   = optional(number)
    port_range_max   = optional(number)
    remote_ip_prefix = optional(string, "0.0.0.0/0")
  }))
  default = []
}
