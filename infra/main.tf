# Configure Azure Provider with OIDC details passed from GitHub Actions
# (Provider configuration is in providers.tf)

# --- Resource Naming Convention using Azure CAF Provider ---

resource "azurecaf_name" "rg" {
  name          = var.project_prefix
  resource_type = "azurerm_resource_group"
  prefixes      = ["rg"]
  suffixes      = [var.environment, var.location]
  separator     = "-"
  clean_input   = true
  passthrough   = false # Generate CAF compliant name
}

resource "azurecaf_name" "acr" {
  name          = var.project_prefix
  resource_type = "azurerm_container_registry"
  prefixes      = ["acr"]
  suffixes      = [var.environment] # ACR names are globally unique
  separator     = ""
  clean_input   = true
  passthrough   = false
}

resource "azurecaf_name" "log" {
  name          = var.project_prefix
  resource_type = "azurerm_log_analytics_workspace"
  prefixes      = ["log"]
  suffixes      = [var.environment, var.location]
  separator     = "-"
  clean_input   = true
  passthrough   = false
}

resource "azurecaf_name" "kv" {
  name          = var.project_prefix
  resource_type = "azurerm_key_vault"
  prefixes      = ["kv"]
  suffixes      = [var.environment, var.location] # KV names are globally unique but suffix helps readability
  separator     = "-"
  clean_input   = true
  passthrough   = false
}


resource "azurecaf_name" "vnet" {
  name          = var.project_prefix
  resource_type = "azurerm_virtual_network"
  prefixes      = ["vnet"]
  suffixes      = [var.environment, var.location]
  separator     = "-"
  clean_input   = true
  passthrough   = false
}

resource "azurecaf_name" "cae_subnet" {
  name          = "cae" # Specific name for the container apps subnet
  resource_type = "azurerm_subnet"
  prefixes      = ["snet"]
  suffixes      = [var.environment]
  separator     = "-"
  clean_input   = true
  passthrough   = false
}

resource "azurecaf_name" "cae" {
  name          = var.project_prefix
  resource_type = "azurerm_container_app_environment"
  prefixes      = ["cae"]
  suffixes      = [var.environment, var.location]
  separator     = "-"
  clean_input   = true
  passthrough   = false
}

# --- Core Resources ---

data "azurerm_client_config" "current" {} # Get current client config for tenant ID

resource "azurerm_resource_group" "main" {
  name     = azurecaf_name.rg.result
  location = var.location
  tags     = merge(var.tags, { Environment = var.environment })
}

resource "azurerm_container_registry" "main" {
  name                = azurecaf_name.acr.result
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.container_registry_sku
  admin_enabled       = false
  tags                = merge(var.tags, { Environment = var.environment })
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = azurecaf_name.log.result
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = merge(var.tags, { Environment = var.environment })
}

resource "azurerm_key_vault" "main" {
  name                        = azurecaf_name.kv.result
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = var.key_vault_sku_name
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false # Set to true for production if needed

  # Enable RBAC for authorization instead of access policies
  enable_rbac_authorization = true

  # Network ACLs (optional - restrict access)
  # network_acls {
  #   default_action = "Deny"
  #   bypass         = "AzureServices" # Allow Azure services (like Container Apps)
  #   # Add specific IP ranges or VNet subnet IDs if needed
  #   # virtual_network_subnet_ids = [azurerm_subnet.container_apps.id] # Allow access from CAE subnet
  # }

  tags = merge(var.tags, { Environment = var.environment })
}

resource "azurerm_virtual_network" "main" {
  name                = azurecaf_name.vnet.result
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space
  tags                = merge(var.tags, { Environment = var.environment })
}

resource "azurerm_subnet" "container_apps" {
  name                 = azurecaf_name.cae_subnet.result
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.container_apps_subnet_address_prefix]

  delegation {
    name = "Microsoft.App.environments"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# --- Module Instantiation ---

module "container_app_environment" {
  source = "./modules/container_app_environment"

  name                       = azurecaf_name.cae.result
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  infrastructure_subnet_id   = azurerm_subnet.container_apps.id
  tags                       = merge(var.tags, { Environment = var.environment })
}

module "container_apps" {
  source = "./modules/container_app"
  for_each = var.container_apps

  app_name                       = each.key
  project_prefix                 = var.project_prefix
  environment                    = var.environment
  location                       = azurerm_resource_group.main.location
  resource_group_name            = azurerm_resource_group.main.name
  container_app_environment_id   = module.container_app_environment.id
  container_registry_login_server = azurerm_container_registry.main.login_server
  container_registry_id          = azurerm_container_registry.main.id
  key_vault_id                   = azurerm_key_vault.main.id # Pass Key Vault ID

  image_name                     = each.value.image_name
  image_tag                      = "latest" # Overridden by CI/CD
  target_port                    = each.value.target_port
  external_ingress_enabled       = each.value.external_ingress
  cpu                            = each.value.cpu
  memory                         = each.value.memory
  min_replicas                   = each.value.min_replicas
  max_replicas                   = each.value.max_replicas
  tags                           = merge(var.tags, { Environment = var.environment, Service = each.key })

  # Pass non-secret environment variables directly
  environment_variables = try(each.value.env_vars, {})

  # Construct the secrets map expected by the module (with full Key Vault Secret IDs)
  secrets = {
    for secret_name, kv_secret_name in try(each.value.secrets, {}) :
    secret_name => {
      # Construct the Key Vault Secret ID using the vault URI and the secret name from the variable
      key_vault_secret_id = "${azurerm_key_vault.main.vault_uri}secrets/${kv_secret_name}"
      # value = null # Ensure value is null when using key_vault_secret_id
    }
  }

  depends_on = [
    azurerm_container_registry.main,
    module.container_app_environment,
    azurerm_key_vault.main # Ensure Key Vault exists before apps that might need its secrets
  ]
}