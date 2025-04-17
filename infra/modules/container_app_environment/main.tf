resource "azurerm_container_app_environment" "cae" {
  name                       = var.name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  log_analytics_workspace_id = var.log_analytics_workspace_id
  infrastructure_subnet_id   = var.infrastructure_subnet_id
  tags                       = var.tags

  # Conditional configuration for workload profiles
  dynamic "workload_profile" {
    # Only include this block if it's a Dedicated plan (minimum_nodes is set)
    for_each = var.minimum_nodes != null ? [1] : []
    content {
      name                  = var.workload_profile_name
      workload_profile_type = var.workload_profile_name # Assuming name matches type for Dedicated, e.g., "D4"
      minimum_count         = var.minimum_nodes
      maximum_count         = var.maximum_nodes
    }
  }

  # If it's a Consumption plan (minimum_nodes is null), ensure no workload_profile block is added.
  # The absence of the block implies Consumption plan.
}