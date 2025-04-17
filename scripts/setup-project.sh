#!/bin/bash

# Orchestration script to set up Azure resources for TF Backend,
# Azure AD OIDC, and configure GitHub Environment secrets/variables.
# Uses Azure CLI (az) and GitHub CLI (gh).

set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Causes pipelines to fail on the first command that fails

# --- Configuration ---

# Environment definitions (Customize these names/prefixes as needed)
declare -A ENV_CONFIG
ENV_CONFIG[dev,app_rg_suffix]="dev-app"        # e.g., rg-ld-hack-dev-app-uksouth
ENV_CONFIG[dev,project_prefix]="hackappdev"       # Matches infra/env/dev.tfvars
ENV_CONFIG[dev,tfvars_file]="env/dev.tfvars"
ENV_CONFIG[dev,run_canary]="false"
ENV_CONFIG[dev,location]="uksouth"             # Location for the app resources

# ENV_CONFIG[staging,app_rg_suffix]="stg-app"    # e.g., rg-ld-hack-stg-app-uksouth
# ENV_CONFIG[staging,project_prefix]="hackappstg" # Matches infra/env/staging.tfvars
# ENV_CONFIG[staging,tfvars_file]="env/staging.tfvars"
# ENV_CONFIG[staging,run_canary]="true"
# ENV_CONFIG[staging,location]="uksouth"         # Location for the app resources

ENV_CONFIG[prod,app_rg_suffix]="prd-app"       # e.g., rg-ld-hack-prd-app-eastus
ENV_CONFIG[prod,project_prefix]="hackappprd"   # Matches infra/env/prod.tfvars
ENV_CONFIG[prod,tfvars_file]="env/prod.tfvars"
ENV_CONFIG[prod,run_canary]="true"
ENV_CONFIG[prod,location]="uksouth"             # Location for the app resources

# --- Helper Functions ---

check_prereqs() {
    echo "Checking prerequisites..."
    if ! command -v az &> /dev/null; then
        echo "Error: Azure CLI (az) not found. Please install it and run 'az login'."
        exit 1
    fi
    if ! command -v gh &> /dev/null; then
        echo "Error: GitHub CLI (gh) not found. Please install it and run 'gh auth login'."
        exit 1
    fi
    if ! az account show > /dev/null 2>&1; then
        echo "Error: Not logged into Azure. Please run 'az login'."
        exit 1
    fi
     if ! gh auth status > /dev/null 2>&1; then
        echo "Error: Not logged into GitHub CLI. Please run 'gh auth login'."
        exit 1
    fi
    echo "Prerequisites met."
}

setup_tf_backend() {
    local base_name=$1
    local location=$2
    local subscription_id=$3

    TF_STATE_RG="rg-${base_name}-tfstate-${location}"
    # Storage account names must be 3-24 chars, lowercase letters and numbers only.
    # Generate a unique suffix as base_name might be too long/invalid.
    local unique_suffix=$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)
    TF_STATE_STORAGE_ACCOUNT="${base_name//-/}${unique_suffix}tfstate" # Remove hyphens, add suffix
    TF_STATE_STORAGE_ACCOUNT=$(echo "${TF_STATE_STORAGE_ACCOUNT}" | tr '[:upper:]' '[:lower:]') # Ensure lowercase
    TF_STATE_STORAGE_ACCOUNT=${TF_STATE_STORAGE_ACCOUNT:0:24} # Truncate if needed
    TF_STATE_CONTAINER="tfstate"

    echo "--- Setting up Terraform Backend ---"
    echo "Resource Group: $TF_STATE_RG"
    echo "Storage Account: $TF_STATE_STORAGE_ACCOUNT"
    echo "Container: $TF_STATE_CONTAINER"

    # Create Resource Group if it doesn't exist
    if ! az group show --name "$TF_STATE_RG" &> /dev/null; then
        echo "Creating Resource Group: $TF_STATE_RG..."
        az group create --name "$TF_STATE_RG" --location "$location" --output none
        echo "Resource Group created."
    else
        echo "Resource Group '$TF_STATE_RG' already exists."
    fi

    # Create Storage Account if it doesn't exist
    if ! az storage account show --name "$TF_STATE_STORAGE_ACCOUNT" --resource-group "$TF_STATE_RG" &> /dev/null; then
        echo "Creating Storage Account: $TF_STATE_STORAGE_ACCOUNT..."
        az storage account create --name "$TF_STATE_STORAGE_ACCOUNT" \
            --resource-group "$TF_STATE_RG" \
            --location "$location" \
            --sku Standard_LRS \
            --encryption-services blob \
            --output none
         echo "Storage Account created."
    else
        echo "Storage Account '$TF_STATE_STORAGE_ACCOUNT' already exists."
    fi

    # Create Storage Container if it doesn't exist
    if ! az storage container show --name "$TF_STATE_CONTAINER" --account-name "$TF_STATE_STORAGE_ACCOUNT" --auth-mode login &> /dev/null; then
        echo "Creating Storage Container: $TF_STATE_CONTAINER..."
        az storage container create --name "$TF_STATE_CONTAINER" \
            --account-name "$TF_STATE_STORAGE_ACCOUNT" \
            --auth-mode login \
            --output none
        echo "Storage Container created."
    else
        echo "Storage Container '$TF_STATE_CONTAINER' already exists."
    fi
    echo "Terraform Backend setup complete."
}

setup_oidc() {
    local base_name=$1
    local subscription_id=$2
    local github_repo=$3 # owner/repo format
    # Use the keys from ENV_CONFIG to determine which environments to set up
    local environments_to_setup=()
    while IFS=',' read -r key _; do
        if [[ $key != *,* ]]; then # Avoid processing the second part of the key
           environments_to_setup+=("$key")
        fi
    done < <(echo "${!ENV_CONFIG[@]}" | tr ' ' '\n' | cut -d',' -f1 | sort -u)


    local ad_app_name="app-${base_name}-github-oidc"

    echo "--- Setting up Azure AD OIDC ---"
    echo "AD App Name: $ad_app_name"

    # Create/Get AD Application
    echo "Checking for AD App: $ad_app_name..."
    local app_object_id=$(az ad app list --display-name "$ad_app_name" --query "[].id" -o tsv)
    if [ -z "$app_object_id" ]; then
        echo "Creating AD App..."
        app_object_id=$(az ad app create --display-name "$ad_app_name" --query "id" -o tsv)
        echo "AD App created with Object ID: $app_object_id"
    else
        echo "AD App already exists with Object ID: $app_object_id"
    fi

    AZURE_CLIENT_ID=$(az ad app show --id "$app_object_id" --query "appId" -o tsv)
    AZURE_TENANT_ID=$(az account show --query "tenantId" -o tsv)
    AZURE_SUBSCRIPTION_ID=$subscription_id # Passed as argument
    echo "Client ID: $AZURE_CLIENT_ID"
    echo "Tenant ID: $AZURE_TENANT_ID"

    # Create/Get Service Principal
    echo "Checking for Service Principal..."
    local sp_object_id=$(az ad sp list --display-name "$ad_app_name" --query "[?appId=='$AZURE_CLIENT_ID'].id" -o tsv --all)
    if [ -z "$sp_object_id" ]; then
        echo "Creating Service Principal..."
        # Wait for AD App propagation
        sleep 15
        sp_object_id=$(az ad sp create --id "$app_object_id" --query "id" -o tsv)
        echo "Service Principal created with Object ID: $sp_object_id"
    else
        echo "Service Principal already exists with Object ID: $sp_object_id"
    fi

    # Assign Contributor Role at Subscription Scope (for simplicity)
    echo "Assigning 'Contributor' role to SP ($sp_object_id) at subscription scope..."
    if ! az role assignment create \
        --role "Contributor" \
        --assignee-object-id "$sp_object_id" \
        --assignee-principal-type ServicePrincipal \
        --scope "/subscriptions/$subscription_id"; then
        echo "Warning: Failed to assign 'Contributor' role at subscription scope. Might already exist or lack permissions. Check Azure portal."
    else
        echo "'Contributor' role assigned at subscription scope."
    fi

    # Create Federated Credentials for each environment defined in ENV_CONFIG
    echo "Setting up Federated Credentials for environments: ${environments_to_setup[*]}"
    for env in "${environments_to_setup[@]}"; do
        local credential_name="github-${env}"
        local subject_claim="repo:${github_repo}:environment:${env}"
        echo "Checking Federated Credential '$credential_name' for Subject '$subject_claim'..."

        local existing_cred=$(az ad app federated-credential list --id "$app_object_id" --query "[?name=='$credential_name']" -o tsv)
        if [ -z "$existing_cred" ]; then
            echo "Creating Federated Credential '$credential_name'..."
            az ad app federated-credential create --id "$app_object_id" --parameters \
            '{
                "name": "'"$credential_name"'",
                "issuer": "https://token.actions.githubusercontent.com",
                "subject": "'"$subject_claim"'",
                "description": "GitHub Actions OIDC for '"$github_repo"' ('"$env"')",
                "audiences": ["api://AzureADTokenExchange"]
            }' --output none
            echo "Federated Credential '$credential_name' created."
        else
            echo "Federated Credential '$credential_name' already exists."
        fi
    done
    echo "Azure AD OIDC setup complete."
}

configure_github_env() {
    local env=$1
    local github_repo=$2 # owner/repo
    local base_name=$3
    # local location=$4 # Location for app RG is now defined in ENV_CONFIG

    echo "--- Configuring GitHub Environment: $env ---"

    # Check/Create GitHub Environment using API (gh environment create not available)
    echo "Checking if GitHub Environment '$env' exists..."
    if ! gh api "repos/$github_repo/environments/$env" --silent; then
        echo "Creating GitHub Environment '$env'..."
        # Attempt to create - might fail if user lacks permissions, but script continues
        gh api --method PUT "repos/$github_repo/environments/$env" -f wait=false --silent || echo "Warning: Failed to create GitHub Environment '$env'. Please ensure it exists or create it manually."
        echo "GitHub Environment '$env' creation attempted."
    else
        echo "GitHub Environment '$env' already exists."
    fi

    # Get environment-specific config from ENV_CONFIG associative array
    local app_rg_suffix=${ENV_CONFIG[$env,app_rg_suffix]}
    local project_prefix=${ENV_CONFIG[$env,project_prefix]}
    local tfvars_file=${ENV_CONFIG[$env,tfvars_file]}
    local run_canary=${ENV_CONFIG[$env,run_canary]}
    local app_location=${ENV_CONFIG[$env,location]}
    local app_rg_name="rg-${base_name}-${app_rg_suffix}-${app_location}" # Construct app RG name

    # Set Secrets
    echo "Setting secrets for '$env' environment..."
    gh secret set AZURE_CLIENT_ID --env "$env" --body "$AZURE_CLIENT_ID" --repo "$github_repo"
    gh secret set AZURE_TENANT_ID --env "$env" --body "$AZURE_TENANT_ID" --repo "$github_repo"
    gh secret set AZURE_SUBSCRIPTION_ID --env "$env" --body "$AZURE_SUBSCRIPTION_ID" --repo "$github_repo"
    gh secret set TF_STATE_RG --env "$env" --body "$TF_STATE_RG" --repo "$github_repo"
    gh secret set TF_STATE_STORAGE_ACCOUNT --env "$env" --body "$TF_STATE_STORAGE_ACCOUNT" --repo "$github_repo"
    gh secret set TF_STATE_CONTAINER --env "$env" --body "$TF_STATE_CONTAINER" --repo "$github_repo"
    echo "Secrets set."

    # Set Variables
    echo "Setting variables for '$env' environment..."
    gh variable set TF_VARS_FILE --env "$env" --body "$tfvars_file" --repo "$github_repo"
    gh variable set PROJECT_PREFIX --env "$env" --body "$project_prefix" --repo "$github_repo"
    gh variable set RESOURCE_GROUP_NAME --env "$env" --body "$app_rg_name" --repo "$github_repo" # Set the target app RG name
    gh variable set RUN_CANARY --env "$env" --body "$run_canary" --repo "$github_repo"
    echo "Variables set."

    echo "GitHub Environment '$env' configured."
}

# --- Main Script ---

# Input Parameters
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <azure-subscription-id> <base-name> <azure-location-for-tfstate> <github-repo>"
    echo "  <azure-subscription-id>: Your Azure Subscription ID"
    echo "  <base-name>: A short name for project resources (e.g., 'ld-hack', 'myproj')"
    echo "  <azure-location-for-tfstate>: Azure location for TF state resources (e.g., 'uksouth')"
    echo "  <github-repo>: Your GitHub repository in 'owner/repo' format"
    exit 1
fi

ARG_SUBSCRIPTION_ID="$1"
ARG_BASE_NAME="$2"
ARG_TF_STATE_LOCATION="$3" # Location specifically for TF state
ARG_GITHUB_REPO="$4"

# Determine environments to set up from the ENV_CONFIG keys
ENVIRONMENTS_TO_SETUP=()
while IFS=',' read -r key _; do
    if [[ $key != *,* ]]; then # Avoid processing the second part of the key
        ENVIRONMENTS_TO_SETUP+=("$key")
    fi
done < <(echo "${!ENV_CONFIG[@]}" | tr ' ' '\n' | cut -d',' -f1 | sort -u)


# --- Execution ---

check_prereqs

# Set Azure context
echo "Setting Azure subscription context to $ARG_SUBSCRIPTION_ID..."
az account set --subscription "$ARG_SUBSCRIPTION_ID"

# Setup shared TF Backend
setup_tf_backend "$ARG_BASE_NAME" "$ARG_TF_STATE_LOCATION" "$ARG_SUBSCRIPTION_ID"

# Setup shared OIDC App/SP with Federated Credentials per environment
setup_oidc "$ARG_BASE_NAME" "$ARG_SUBSCRIPTION_ID" "$ARG_GITHUB_REPO" "${ENVIRONMENTS_TO_SETUP[@]}"

# Configure each GitHub Environment defined in ENV_CONFIG
echo "Configuring GitHub Environments: ${ENVIRONMENTS_TO_SETUP[*]}"
for env in "${ENVIRONMENTS_TO_SETUP[@]}"; do
    configure_github_env "$env" "$ARG_GITHUB_REPO" "$ARG_BASE_NAME"
done

echo ""
echo "------------------------------------------------------------------"
echo " Project Setup Complete!"
echo "------------------------------------------------------------------"
echo " - Azure Resources for Terraform Backend created/verified in $ARG_TF_STATE_LOCATION."
echo " - Azure AD Application/SP for OIDC created/verified."
echo " - Federated Credentials added for environments: ${ENVIRONMENTS_TO_SETUP[*]}"
echo " - GitHub Environments (${ENVIRONMENTS_TO_SETUP[*]}) configured with necessary secrets and variables."
echo ""
echo "You should now be able to trigger deployments via pushes to 'main' (for dev)"
echo "or manually via the 'CD - Trigger Deployment' workflow."
echo "------------------------------------------------------------------"