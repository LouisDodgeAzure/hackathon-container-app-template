# --- Core Infrastructure Outputs ---

output "resource_group_name" {
  description = "The name of the Azure Resource Group."
  value       = azurerm_resource_group.main.name
}

output "location" {
  description = "The Azure region where resources are deployed."
  value       = azurerm_resource_group.main.location
}

output "container_registry_login_server" {
  description = "The login server for the Azure Container Registry."
  value       = azurerm_container_registry.main.login_server
}

output "container_registry_id" {
  description = "The resource ID of the Azure Container Registry."
  value       = azurerm_container_registry.main.id
}

output "log_analytics_workspace_id" {
  description = "The resource ID of the Log Analytics Workspace."
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_customer_id" {
  description = "The Customer ID (Workspace ID) of the Log Analytics Workspace."
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

# --- Container App Environment Outputs ---

output "container_app_environment_id" {
  description = "The resource ID of the Container App Environment."
  value       = module.container_app_environment.id
}

output "container_app_environment_name" {
  description = "The name of the Container App Environment."
  value       = module.container_app_environment.name
}

output "container_app_environment_default_domain" {
  description = "The default domain suffix for apps within the environment."
  value       = module.container_app_environment.default_domain
}

# --- Container App Outputs ---

output "container_apps_details" {
  description = "Details for each deployed Container App."
  value = {
    for k, app in module.container_apps : k => {
      name = app.name
      id   = app.id
      fqdn = app.fqdn # Will be 'N/A (Internal Ingress)' for internal apps
      latest_revision_name = app.latest_revision_name
      identity_principal_id = app.identity_principal_id
    }
  }
  # Sensitive = true # Mark as sensitive if it contains potentially sensitive FQDNs
}

output "container_apps_fqdns" {
  description = "Map of externally accessible Container App names to their FQDNs."
  value = {
    for k, app in module.container_apps : k => app.fqdn if app.fqdn != "N/A (Internal Ingress)"
  }
}