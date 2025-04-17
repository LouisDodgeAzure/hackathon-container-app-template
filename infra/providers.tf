terraform {
  required_version = ">= 1.3"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azurecaf = {
      source  = "aztfmod/azurecaf"
      version = "~> 1.2" # Use an appropriate version
    }
  }
}

provider "azurerm" {
  features {}

  # Configure OIDC authentication for GitHub Actions
  # Assumes environment variables AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID,
  # and ARM_OIDC_TOKEN are set by the GitHub Actions workflow.
  use_oidc = true
}

# No specific provider block needed for azurecaf unless customizing its behavior