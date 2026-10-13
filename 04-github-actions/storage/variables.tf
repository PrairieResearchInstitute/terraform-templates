variable "os_cloud" {
  type        = string
  description = "Name of the entry in clouds.yaml that holds your credentials."
  default     = "my-cloud"
}

variable "volumes" {
  type        = map(number)
  description = "Map of VM name => data volume size in GB. Each KEY must equal instance_name in that VM's folder."
}
