output "id" {
  description = "The resource ID of the Container App."
  value       = azurerm_container_app.app.id
}

output "name" {
  description = "The name of the Container App."
  value       = azurerm_container_app.app.name
}

output "fqdn" {
  description = "The Fully Qualified Domain Name (FQDN) of the Container App's latest revision (only available for external ingress)."
  value       = var.external_ingress_enabled ? azurerm_container_app.app.latest_revision_fqdn : "N/A (Internal Ingress)"
}

output "latest_revision_name" {
  description = "The name of the latest revision of the Container App."
  value       = azurerm_container_app.app.latest_revision_name
}

output "identity_principal_id" {
  description = "The Principal ID of the System Assigned Managed Identity for the Container App."
  value       = azurerm_container_app.app.identity[0].principal_id
}