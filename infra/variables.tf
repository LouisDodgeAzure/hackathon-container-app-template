variable "resource_group_name" {
  type        = string
  description = "The name of the Azure Resource Group where resources will be created."
}

variable "location" {
  type        = string
  description = "The Azure region where resources will be deployed (e.g., 'uksouth', 'eastus')."
}

variable "environment" {
  type        = string
  description = "The deployment environment name (e.g., 'dev', 'staging', 'prod')."
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_prefix" {
  type        = string
  description = "A short prefix used for naming resources to ensure uniqueness and identification (e.g., 'hackapp')."
  validation {
    condition     = length(var.project_prefix) > 0 && length(var.project_prefix) <= 10
    error_message = "Project prefix must be between 1 and 10 characters."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to apply to all created resources."
  default = {
    Project     = "MultiContainerApp"
    Environment = "Unknown" # Will be overridden by main.tf using var.environment
    ManagedBy   = "Terraform"
  }
}

variable "container_registry_sku" {
  type        = string
  description = "The SKU for the Azure Container Registry (e.g., 'Basic', 'Standard', 'Premium')."
  default     = "Basic" # Basic is often sufficient for hackathons
}

variable "key_vault_sku_name" {
  type        = string
  description = "The SKU for the Azure Key Vault (e.g., 'standard', 'premium')."
  default     = "standard"
}

variable "container_apps_environment_compute" {
  type = object({
    workload_profile_name = string
    minimum_nodes         = number
    maximum_nodes         = number
  })
  description = "Configuration for the Container Apps Environment workload profile."
  default = {
    # Using Consumption profile as default for cost-effectiveness in hackathons
    workload_profile_name = "Consumption"
    minimum_nodes         = null # Not applicable for Consumption
    maximum_nodes         = null # Not applicable for Consumption
  }
  # Add validation if needed for dedicated plans
}

variable "vnet_address_space" {
  type        = list(string)
  description = "The address space for the Virtual Network used by the Container Apps Environment."
  default     = ["10.0.0.0/16"]
}

variable "container_apps_subnet_address_prefix" {
  type        = string
  description = "The address prefix for the subnet dedicated to the Container Apps Environment."
  default     = "10.0.1.0/24"
}

variable "internal_ingress_subnet_address_prefix" {
  type        = string
  description = "The address prefix for the subnet dedicated to internal ingress controllers if needed (optional)."
  default     = "10.0.2.0/24" # Example, adjust if needed
}


variable "container_apps" {
  type = map(object({
    image_name             = string # Name of the image in ACR (without tag/registry)
    target_port            = number # The port the container listens on
    external_ingress       = bool   # Whether the app should be accessible from the internet
    cpu                    = number # CPU cores allocated (e.g., 0.25, 0.5, 1.0)
    memory                 = string # Memory allocated (e.g., "0.5Gi", "1Gi")
    min_replicas           = number # Minimum number of replicas
    max_replicas           = number # Maximum number of replicas
    # Add other container-specific settings like environment variables, secrets, etc. here
    env_vars = optional(map(string), {}) # Non-secret env vars
    # Secrets should reference Key Vault names defined here, module will construct the ID
    secrets = optional(map(string), {}) # Map secret name in container to secret name in Key Vault
  }))
  description = "A map defining the configuration for each container app to be deployed."
  default = {
    # Example: Define your services here
    "service1" = {
      image_name       = "service1"
      target_port      = 8080
      external_ingress = true # Example: Make service1 public
      cpu              = 0.25
      memory           = "0.5Gi"
      min_replicas     = 0 # Scale to zero for dev/staging cost savings
      max_replicas     = 1
      env_vars = {
        "LOG_LEVEL" = "DEBUG" # Example non-secret env var
      }
      secrets = {
        "API_KEY" = "service1-api-key" # Mounts secret named 'service1-api-key' from KV as env var API_KEY
      }
    },
    "service2" = {
      image_name       = "service2"
      target_port      = 5000
      external_ingress = false # Example: Make service2 internal
      cpu              = 0.25
      memory           = "0.5Gi"
      min_replicas     = 0
      max_replicas     = 1
      secrets = {
         "DATABASE_URL" = "service2-db-connection" # Mounts secret named 'service2-db-connection' from KV
      }
    }
  }
}