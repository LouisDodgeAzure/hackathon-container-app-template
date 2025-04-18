#!/usr/bin/env bash

# Orchestration script to set up Azure resources for TF Backend,
# Azure AD OIDC, and configure GitHub Environment secrets/variables.
# Uses Azure CLI (az) and GitHub CLI (gh).
# =============================================================================
set -euo pipefail

# ── Logging helpers ───────────────────────────────────────────────────────────
RED=$'\e[31m'; GREEN=$'\e[32m'; NC=$'\e[0m'
log(){ printf '%s[%s]%s %s\n' "$GREEN" "$(date +'%H:%M:%S')" "$NC" "$*"; }
die(){ printf '%s[%s]%s %s\n' "$RED"   "$(date +'%H:%M:%S')" "$NC" "$*" >&2; exit 1; }
trap 'die "Script aborted at line $LINENO."' ERR

# ── Azure CLI wrapper for Windows ─────────────────────────────────────────────
AZ(){
  if [[ $(uname -s) =~ MINGW|MSYS ]]; then
    MSYS_NO_PATHCONV=1 az "$@"
  else
    az "$@"
  fi
}

# ── Require GH CLI ≥2.34.0 for env commands ────────────────────────────────────
ensure_gh_version(){
  local required="2.34.0" got
  got=$(gh --version | head -n1 | awk '{print $3}')
  if [[ "$(printf '%s\n%s' "$required" "$got" | sort -V | head -n1)" != "$required" ]]; then
    die "gh CLI ≥ $required required; you have $got."
  fi
}

# ── Per‑environment config ────────────────────────────────────────────────────
declare -A ENV_CONFIG
ENV_CONFIG[dev,app_rg_suffix]=dev-app
ENV_CONFIG[dev,project_prefix]=hackappdev
ENV_CONFIG[dev,tfvars_file]=env/dev.tfvars
ENV_CONFIG[dev,run_canary]=false
ENV_CONFIG[dev,location]=uksouth

ENV_CONFIG[prod,app_rg_suffix]=prd-app
ENV_CONFIG[prod,project_prefix]=hackappprd
ENV_CONFIG[prod,tfvars_file]=env/prod.tfvars
ENV_CONFIG[prod,run_canary]=true
ENV_CONFIG[prod,location]=uksouth

# ── Prerequisites ─────────────────────────────────────────────────────────────
check_prereqs(){
  log "Checking prerequisites…"
  for cmd in az gh jq; do
    command -v "$cmd" &>/dev/null || die "'$cmd' not found"
  done
  AZ account show > /dev/null   || die "Please run 'az login'"
  gh auth status > /dev/null   || die "Please run 'gh auth login'"
  ensure_gh_version
  log "All prerequisites met (gh v$(gh --version | head -n1 | awk '{print $3}'))."
}

# ── Verify GitHub repo access ─────────────────────────────────────────────────
check_repo_access(){
  log "Verifying access to repo '$REPO'…"
  gh api "repos/$REPO" > /dev/null 2>&1 \
    || die "Cannot access '$REPO'. Ensure GH token has 'repo' & 'workflow' scopes."
  log "GitHub repo is reachable."
}

# ── Terraform backend setup (idempotent) ─────────────────────────────────────
setup_tf_backend(){
  local base=$1 loc=$2 sub=$3
  local RG="rg-${base}-tfstate-${loc}"
  local clean=${base//[-_]/}
  local suffix=${sub//-/}; suffix=${suffix:0:6}
  local SA=$(printf "%s%stfstate" "$clean" "$suffix" \
            | tr '[:upper:]' '[:lower:]' | cut -c1-24)
  local CONT=tfstate

  log "Terraform backend → RG:$RG  SA:$SA  container:$CONT"
  AZ group create --name "$RG" --location "$loc" --subscription "$sub" --output none || true
  AZ storage account show --name "$SA" --resource-group "$RG" --subscription "$sub" > /dev/null 2>&1 || \
    AZ storage account create --name "$SA" --resource-group "$RG" --location "$loc" \
      --sku Standard_LRS --encryption-services blob --subscription "$sub" --output none
  AZ storage container show --name "$CONT" --account-name "$SA" --auth-mode login > /dev/null 2>&1 || \
    AZ storage container create --name "$CONT" --account-name "$SA" --auth-mode login --output none

  export TF_STATE_RG=$RG
  export TF_STATE_STORAGE_ACCOUNT=$SA
  export TF_STATE_CONTAINER=$CONT
  log "Terraform backend ready."
}

# ── Azure AD OIDC setup ───────────────────────────────────────────────────────
setup_oidic(){
  local base=$1 sub=$2 repo=$3
  local APP="app-${base}-github-oidc"
  log "Configuring Azure AD app '$APP'…"

  local appId
  appId=$(AZ ad app list --display-name "$APP" --query "[0].id" -o tsv)
  if [[ -z $appId ]]; then
    appId=$(AZ ad app create --display-name "$APP" -o tsv)
    log "Created AD App ($appId)."
  fi

  export AZURE_CLIENT_ID=$(AZ ad app show --id "$appId" --query appId -o tsv)
  export AZURE_TENANT_ID=$(AZ account show --query tenantId -o tsv)
  export AZURE_SUBSCRIPTION_ID=$sub

  local sp
  sp=$(AZ ad sp list --display-name "$APP" --query "[?appId=='$AZURE_CLIENT_ID'].id" -o tsv --all)
  if [[ -z $sp ]]; then
    sleep 15
    sp=$(AZ ad sp create --id "$appId" -o tsv)
    log "Created Service Principal ($sp)."
  fi

  if ! AZ role assignment list --assignee "$sp" --scope "/subscriptions/$sub" \
       --query "[?roleDefinitionName=='Contributor']" -o tsv | grep -q .; then
    log "Assigning 'Contributor' role."
    AZ role assignment create --role Contributor --assignee "$sp" \
      --scope "/subscriptions/$sub" --subscription "$sub" --only-show-errors
  else
    log "'Contributor' role already assigned."
  fi

  local envs=$(printf '%s\n' "${!ENV_CONFIG[@]}" | cut -d',' -f1 | sort -u)
  for e in $envs; do
    local cred="github-${e}"
    local subj="repo:${repo}:environment:${e}"
    if ! AZ ad app federated-credential list --id "$appId" --query "[?name=='$cred']" -o tsv | grep -q .; then
      log "Adding federated credential '$cred'."
      AZ ad app federated-credential create --id "$appId" \
        --parameters "{\"name\":\"$cred\",\"issuer\":\"https://token.actions.githubusercontent.com\",\"subject\":\"$subj\",\"audiences\":[\"api://AzureADTokenExchange\"]}" \
        --only-show-errors --output none
    else
      log "Federated credential '$cred' exists."
    fi
  done

  log "Azure AD OIDC complete."
}

# ── GitHub environment setup ──────────────────────────────────────────────────
configure_github_env(){
  local env=$1
  log "Configuring GitHub environment '$env'…"

  # 1) Create environment via API if missing
  if gh api "repos/$REPO/environments/$env" > /dev/null 2>&1; then
    log "Environment '$env' exists."
  else
    log "Creating environment '$env'…"
    gh api --method PUT -H "Accept: application/vnd.github+json" repos/$REPO/environments/$env > /dev/null \
      || die "Failed to create environment '$env'."
  fi

  # 2) Set secrets
  for s in AZURE_CLIENT_ID AZURE_TENANT_ID AZURE_SUBSCRIPTION_ID \
           TF_STATE_RG TF_STATE_STORAGE_ACCOUNT TF_STATE_CONTAINER; do
    log "Setting secret '$s' in '$env'…"
    gh secret set "$s" --env "$env" --body "${!s}"
  done

  # 3) Set variables
  local loc=${ENV_CONFIG[$env,location]}
  local suffix=${ENV_CONFIG[$env,app_rg_suffix]}
  local tfvars=${ENV_CONFIG[$env,tfvars_file]}
  local prefix=${ENV_CONFIG[$env,project_prefix]}
  local canary=${ENV_CONFIG[$env,run_canary]}
  local rg="rg-${BASE}-${suffix}-${loc}"

  log "Setting variable TF_VARS_FILE…"
  gh variable set TF_VARS_FILE        --env "$env" --body "$tfvars"
  log "Setting variable PROJECT_PREFIX…"
  gh variable set PROJECT_PREFIX      --env "$env" --body "$prefix"
  log "Setting variable RESOURCE_GROUP_NAME…"
  gh variable set RESOURCE_GROUP_NAME --env "$env" --body "$rg"
  log "Setting variable RUN_CANARY…"
  gh variable set RUN_CANARY          --env "$env" --body "$canary"
}

# ── main ─────────────────────────────────────────────────────────────────────
[[ $# -eq 4 ]] || die "Usage: $0 <subscription-id> <base-name> <tfstate-location> <owner/repo>"
SUB=$1; BASE=$2; TF_LOC=$3; REPO=$4
export GH_REPO="$REPO"

check_prereqs
check_repo_access
AZ account set --subscription "$SUB"

setup_tf_backend "$BASE" "$TF_LOC" "$SUB"
setup_oidic       "$BASE" "$SUB" "$REPO"

for env in $(printf '%s\n' "${!ENV_CONFIG[@]}" | cut -d',' -f1 | sort -u); do
  configure_github_env "$env"
done

log "🎉  Setup complete – environments: $(printf '%s ' "${!ENV_CONFIG[@]}" | cut -d',' -f1)"
