# ---------------------------------------------------------------------------------------------------------------------
# REQUIRED PARAMETERS
# These parameters must be supplied when consuming this module.
# ---------------------------------------------------------------------------------------------------------------------
variable "env_name" {
  description = "The name for the inf environment"
  type        = string
}

variable "project_id" {
  description = "The name of the GCP Project where all resources will be launched."
  type        = string
}

variable "region_cidrs" {
  description = "The GCP regions where subnets should be created"
  type        = map(object({
    cidr_range      = string,
    connector_range = string,
    secondary_cidr_blocks = list(object({
      name = string
      cidr_range = string
    }))
  }))
}

# variable "dns_name" {
#   description = "The DNS name for the environment."
#   type        = string
# }

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# These parameters must be supplied when consuming this module.
# ---------------------------------------------------------------------------------------------------------------------

