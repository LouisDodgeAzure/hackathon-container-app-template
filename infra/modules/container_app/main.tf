# --- Resource Naming ---
# Note: azurecaf provider needs to be configured in the root module (which it is)
# We reference it here to generate the name for this specific app instance.
resource "azurecaf_name" "ca" {
  name          = var.app_name # Use the logical app name passed in
  resource_type = "azurerm_container_app"
  prefixes      = [var.project_prefix]
  suffixes      = [var.environment, var.location] # Add environment/location for clarity
  separator     = "-"
  clean_input   = true
  passthrough   = false
}

# --- Container App Resource ---
resource "azurerm_container_app" "app" {
  name                         = azurecaf_name.ca.result
  location                     = var.location # Use location passed to module
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_app_environment_id
  revision_mode                = var.revision_mode # Typically "Multiple" for canary
  tags                         = var.tags

  # System Assigned Managed Identity for ACR Pull
  identity {
    type = "SystemAssigned"
  }

  # Registry configuration for pulling images
  registry {
    server               = var.container_registry_login_server
    identity             = "SystemAssigned" # Use the app's managed identity
  }

  # Secrets definition using Key Vault references passed in var.secrets
  dynamic "secret" {
    for_each = var.secrets # var.secrets should map secret name to { key_vault_secret_id = "..." }
    content {
      name                = secret.key
      key_vault_secret_id = secret.value.key_vault_secret_id
      # identity = "SystemAssigned" # This is implied when using key_vault_secret_id
    }
  }

  # Ingress configuration (external or internal)
  ingress {
    external_enabled = var.external_ingress_enabled
    target_port      = var.target_port
    transport        = "http" # Or "http2", "tcp" depending on the app

    # Traffic weight for canary deployments - Initial revision gets 100%
    # This will be updated by the CI/CD pipeline during canary rollout
    traffic_weight {
      percentage = 100
      latest_revision = true # Direct 100% to the latest stable revision initially
    }

    # Allow insecure connections if needed for internal services or testing
    # allow_insecure_connections = !var.external_ingress_enabled
  }

  # Template defining the container(s)
  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name    = var.app_name # Use the logical app name for the container name
      image   = "${var.container_registry_login_server}/${var.image_name}:${var.image_tag}"
      cpu     = var.cpu
      memory  = var.memory

      # Environment variables
      dynamic "env" {
        for_each = var.environment_variables
        content {
          name  = env.key
          value = env.value
        }
      }

      # Mount secrets as environment variables
      dynamic "env" {
        for_each = var.secrets
        content {
          name        = env.key # Use the secret key as the env var name
          secret_name = env.key # Reference the secret defined above
        }
      }

      # Add probes (liveness, readiness, startup) if needed
      # readiness_probe {
      #   transport = "HTTP"
      #   port = var.target_port
      #   path = "/healthz" # Example path
      # }
      # liveness_probe {
      #   transport = "HTTP"
      #   port = var.target_port
      #   path = "/healthz" # Example path
      #   initial_delay_seconds = 60
      # }
    }

    # Add scaling rules if needed (e.g., based on HTTP traffic, CPU/Memory, Queue length)
    # scale {
    #   rules {
    #     name = "http-scaling-rule"
    #     http {
    #       metadata = {
    #         concurrentRequests = "50" # Scale up when concurrent requests exceed 50
    #       }
    #     }
    #   }
    # }
  }

  # Ensure environment and Key Vault exist before creating the app
  depends_on = [
    azurerm_role_assignment.acr_pull,
    azurerm_role_assignment.key_vault_secrets_user # Ensure KV access is granted first
  ]

  lifecycle {
    ignore_changes = [
      # Ignore changes to tags managed by Azure Policy or other processes
      tags,
      # Ignore changes to ingress traffic weight and image tag, as these are managed by CI/CD pipeline
      ingress[0].traffic_weight,
      template[0].container[0].image,
    ]
  }
}


# --- Role Assignment for ACR Pull ---
# Assign 'AcrPull' role to the Container App's Managed Identity
# Scope this assignment to the specific Container Registry
resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_container_app.app.identity[0].principal_id

  # Ensure the identity principal ID is available before creating the assignment
  depends_on = [azurerm_container_app.app]
}

# --- Role Assignment for Key Vault Access ---
# Assign 'Key Vault Secrets User' role to the Container App's Managed Identity
# Scope this assignment to the specific Key Vault
resource "azurerm_role_assignment" "key_vault_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_container_app.app.identity[0].principal_id

  # Ensure the identity principal ID is available before creating the assignment
  depends_on = [azurerm_container_app.app]
}