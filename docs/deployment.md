# Deployment Workflow

This document describes the CI/CD pipeline implemented using GitHub Actions.

## 1. Overview

The pipeline automates the building, testing, scanning, and deployment of the multi-container application to different Azure environments (`dev`, `prod`, extensible to others like `staging`). It leverages reusable workflows and GitHub Environments for configuration and approvals.

## 2. Workflows

*   **`ci.yml` (Continuous Integration):**
    *   **Trigger:** Push to `main` or feature branches, Pull Requests targeting `main`.
    *   **Purpose:** Build container images, run linters/tests (placeholders included), and scan images for vulnerabilities using Trivy.
    *   **Actions:** Checks out code, sets up Docker Buildx, builds images locally (does *not* push), runs Trivy scan. Fails if high/critical vulnerabilities are found.
*   **`cd-trigger.yml` (Deployment Trigger):**
    *   **Trigger:**
        *   Push to `main` branch (automatically triggers `dev` deployment).
        *   `workflow_dispatch` (manual trigger for `prod` promotion).
    *   **Purpose:** Orchestrates the deployment process by calling the reusable deployment workflow (`cd-deploy.yml`) with environment-specific parameters sourced from GitHub Environments.
    *   **Actions:** Determines target environment and Git reference based on trigger, calls `cd-deploy.yml` passing parameters and secrets from the corresponding GitHub Environment (`dev` or `prod`).
*   **`cd-deploy.yml` (Reusable Deployment):**
    *   **Trigger:** Called by `cd-trigger.yml`.
    *   **Purpose:** Performs the actual build, push, infrastructure update (Terraform), and application deployment (including canary rollout).
    *   **Inputs:** `environment`, `tf_vars_file`, `project_prefix`, `resource_group_name`, `run_canary`, `git_ref`.
    *   **Secrets:** Azure credentials (`AZURE_*`), Terraform state credentials (`TF_STATE_*`). Sourced from the GitHub Environment specified by the caller.
    *   **Jobs:**
        1.  `build-push-images`: Builds images for all services (using checked-out `git_ref`), tags them with commit SHA and `latest_<environment>`, pushes to ACR.
        2.  `deploy-infra`: Runs `terraform init`, `validate`, `plan`, and `apply` using the specified `.tfvars` file and image tag. Ensures infrastructure matches the desired state.
        3.  `canary-deploy` (Conditional: `run_canary == true`):
            *   Updates Container Apps with the new image, creating a new revision suffixed with `canary-<sha>`.
            *   Sets traffic split: 10% to canary, 90% to existing stable (`latest`).
            *   Waits/Smoke Tests.
            *   Sets traffic split: 50% to canary, 50% to stable.
            *   Waits/Smoke Tests.
            *   Sets traffic split: 100% to canary.
            *   Waits/Smoke Tests.
            *   (Optional: Deactivates old stable revision).
        4.  `simple-deploy` (Conditional: `run_canary == false`):
            *   Updates Container Apps directly with the new image (implicitly creates a new revision and shifts 100% traffic).
            *   Waits/Smoke Tests.
        5.  `rollback` (Conceptual: Triggered on failure): Placeholder for potential rollback logic (e.g., activate previous revision).

## 3. Workflow Visualization (Mermaid)

```mermaid
graph LR
    subgraph "GitHub"
        direction TB
        A[Push to main] --> B(Run cd-trigger.yml);
        C[Manual Trigger (workflow_dispatch)] --> B;

        subgraph B[cd-trigger.yml]
           direction TB
           D{Determine Env?}
           D -- push --> E[env=dev];
           D -- dispatch --> F[env=input];
           E --> G[Call cd-deploy.yml];
           F --> G;
        end

        subgraph G[cd-deploy.yml]
           direction TB
           H(Build & Push Images) --> I(Deploy Infra - Terraform Apply);
           I --> J{Canary?};
           J -- Yes --> K[Canary Deploy Steps];
           J -- No --> L[Simple Deploy Steps];
           K --> M((Success/Failure));
           L --> M;
        end

        subgraph K[Canary Deploy]
           direction TB
           K1[Update App (New Revision)] --> K2[Set Traffic 10%];
           K2 --> K3[Wait/Test];
           K3 --> K4[Set Traffic 50%];
           K4 --> K5[Wait/Test];
           K5 --> K6[Set Traffic 100%];
           K6 --> K7[Wait/Test];
        end

        B -- Uses Vars/Secrets --> EnvDev[GitHub Env: dev];
        B -- Uses Vars/Secrets --> EnvProd[GitHub Env: prod];

    end

    subgraph "Azure"
        G -- Deploys --> AzureInfra[Azure Resources (ACR, CAE, CA, KV...)]
    end

    classDef github fill:#eee,stroke:#000,color:#000;
    class A,C,B,D,E,F,G,H,I,J,K,L,M,K1,K2,K3,K4,K5,K6,K7 github;
    classDef azure fill:#0078D4,stroke:#000,color:#fff;
    class AzureInfra,EnvDev,EnvProd azure;

```

## 4. Environment Promotion

1.  **Development (`dev`):** Automatically deployed on every push/merge to the `main` branch via `cd-trigger.yml`. Uses configuration from the `dev` GitHub Environment. Canary deployment is typically disabled (`RUN_CANARY=false` in `dev` environment variables).
2.  **Production (`prod`):**
    *   Manually triggered via `workflow_dispatch` after successful validation in `dev`.
    *   Select `prod` as the target environment.
    *   Optionally specify the *exact same commit SHA* that was validated in `dev`.
    *   Requires approval if configured in the `prod` GitHub Environment settings.
    *   Uses configuration and secrets from the `prod` GitHub Environment.
    *   Performs a canary deployment (`RUN_CANARY=true` in `prod` environment variables).

## 5. Rollback

*   **Automatic (Conceptual):** The `cd-deploy.yml` includes a placeholder `rollback` job triggered on failure. Implementing this would involve scripting logic to identify the last known good revision (e.g., based on tags or previous successful workflow runs) and using `az containerapp revision activate` or modifying traffic weights to revert.
*   **Manual:** Use the Azure Portal or Azure CLI to manually activate a previous stable revision of the Container App(s) if a deployment causes issues.

## 6. Configuration

*   **GitHub Environments:** Critical for managing environment-specific settings. Configure `dev` and `prod` environments in repository `Settings -> Environments`.
    *   **Secrets:** `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `TF_STATE_STORAGE_ACCOUNT`, `TF_STATE_CONTAINER`, `TF_STATE_RG`.
    *   **Variables:** `TF_VARS_FILE`, `PROJECT_PREFIX`, `RESOURCE_GROUP_NAME`, `RUN_CANARY`.
*   **Terraform Backend:** Assumes an Azure Storage backend is configured for Terraform state. The necessary secrets (`TF_STATE_*`) must be added to GitHub Environments.