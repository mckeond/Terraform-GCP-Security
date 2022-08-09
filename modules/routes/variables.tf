variable "project_id" {
  description = "The ID of the project where the routes will be created"
}

variable "network_name" {
  description = "The name of the network where routes will be created"
}

variable "routes" {
  type        = list(map(string))
  description = "List of routes being created in this VPC"
  default     = [10.128.0.0/20 , 10.130.0.0/20]
}

variable "module_depends_on" {
  description = "List of modules or resources this module depends on."
  type        = list(any)
  default     = []
}
