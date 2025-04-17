output "id" {
  description = "The resource ID of the Container App Environment."
  value       = azurerm_container_app_environment.cae.id
}

output "name" {
  description = "The name of the Container App Environment."
  value       = azurerm_container_app_environment.cae.name
}

output "default_domain" {
  description = "The default domain of the Container App Environment."
  value       = azurerm_container_app_environment.cae.default_domain
}

output "static_ip_address" {
  description = "The static IP address of the Container App Environment."
  value       = azurerm_container_app_environment.cae.static_ip_address
}