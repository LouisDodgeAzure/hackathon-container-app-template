variable "app_name" {
  type        = string
  description = "The logical name of the application service (e.g., 'frontend', 'api'). Used for naming."
}

variable "project_prefix" {
  type        = string
  description = "The project prefix used for consistent naming."
}

variable "environment" {
  type        = string
  description = "The deployment environment (e.g., 'dev', 'staging', 'prod')."
}

variable "location" {
  type        = string
  description = "The Azure region where the Container App will be deployed."
}

variable "resource_group_name" {
  type        = string
  description = "The name of the resource group."
}

variable "container_app_environment_id" {
  type        = string
  description = "The resource ID of the Container App Environment where this app will run."
}

variable "container_registry_login_server" {
  type        = string
  description = "The login server of the Azure Container Registry (e.g., 'myacr.azurecr.io')."
}

variable "container_registry_id" {
  type        = string
  description = "The resource ID of the Azure Container Registry (used for role assignment)."
}

variable "key_vault_id" {
  type        = string
  description = "The resource ID of the Azure Key Vault containing the secrets."
}

variable "image_name" {
  type        = string
  description = "The name of the container image in the registry (e.g., 'my-app/frontend')."
}

variable "image_tag" {
  type        = string
  description = "The tag of the container image to deploy (e.g., 'latest', 'v1.0.0', commit SHA)."
  default     = "latest"
}

variable "target_port" {
  type        = number
  description = "The port the container listens on."
}

variable "external_ingress_enabled" {
  type        = bool
  description = "Whether the app should be accessible from the internet."
  default     = false
}

variable "cpu" {
  type        = number
  description = "CPU cores allocated (e.g., 0.25, 0.5)."
}

variable "memory" {
  type        = string
  description = "Memory allocated (e.g., '0.5Gi', '1Gi')."
}

variable "min_replicas" {
  type        = number
  description = "Minimum number of replicas for the container app."
  default     = 0 # Default to scale-to-zero for cost savings
}

variable "max_replicas" {
  type        = number
  description = "Maximum number of replicas for the container app."
  default     = 1
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to apply to the Container App."
  default     = {}
}

variable "environment_variables" {
  type        = map(string)
  description = "A map of environment variables to set in the container (non-secret)."
  default     = {}
}

variable "secrets" {
  type = map(object({
    key_vault_secret_id = optional(string) # For Key Vault references
    value               = optional(string) # For direct secret values (use with caution)
  }))
  description = "A map of secrets to mount in the container. Use key_vault_secret_id for Key Vault references or 'value' for direct secrets (less secure)."
  default     = {}
}

variable "revision_mode" {
  type        = string
  description = "Revision mode for the Container App ('Single' or 'Multiple'). 'Multiple' is needed for canary deployments."
  default     = "Multiple"
}