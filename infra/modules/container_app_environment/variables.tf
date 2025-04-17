variable "name" {
  type        = string
  description = "The name of the Container App Environment."
}

variable "resource_group_name" {
  type        = string
  description = "The name of the resource group where the Container App Environment will be created."
}

variable "location" {
  type        = string
  description = "The Azure region for the Container App Environment."
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "The resource ID of the Log Analytics Workspace to associate with the environment."
}

variable "infrastructure_subnet_id" {
  type        = string
  description = "The resource ID of the subnet delegated to the Container App Environment."
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to apply to the Container App Environment."
  default     = {}
}

# Optional variables for Dedicated workload profiles
variable "workload_profile_name" {
  type        = string
  description = "The name of the workload profile (e.g., 'Consumption', 'D4')."
  default     = "Consumption"
}

variable "minimum_nodes" {
  type        = number
  description = "Minimum number of nodes for the workload profile (only for Dedicated plan)."
  default     = null # Default to null for Consumption plan
}

variable "maximum_nodes" {
  type        = number
  description = "Maximum number of nodes for the workload profile (only for Dedicated plan)."
  default     = null # Default to null for Consumption plan
}