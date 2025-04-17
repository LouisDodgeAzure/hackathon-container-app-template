# Architecture Overview

This document outlines the architecture of the Azure Container Apps multi-container application deployment solution.

## 1. Azure Resources

The core infrastructure is provisioned using Terraform and consists of the following Azure resources per environment (`dev`, `prod`, extensible to others like `staging`):

*   **Resource Group:** A container holding all resources for a specific environment.
*   **Azure Container Registry (ACR):** Stores the built Docker container images for the application services. Accessed securely using Managed Identities.
*   **Log Analytics Workspace:** Collects logs and metrics from the Container Apps Environment for monitoring and diagnostics.
*   **Virtual Network (VNet):** Provides network isolation for the Container Apps Environment.
    *   **Container Apps Subnet:** A dedicated subnet delegated to the Container Apps Environment. Network security is managed by the environment itself.
*   **Azure Key Vault:** Securely stores application secrets (e.g., API keys, database connection strings). Accessed by Container Apps using Managed Identities and RBAC.
*   **Container Apps Environment:** The hosting environment for the container apps. It manages scaling, networking, and logging integration. Can be configured with Consumption or Dedicated plans.
*   **Container Apps (Multiple):** Individual microservices (e.g., `service1`, `service2`) run as container apps within the environment. Each app has:
    *   System-assigned Managed Identity (for ACR pull, Key Vault access).
    *   Ingress settings (external or internal).
    *   Scaling rules (min/max replicas).
    *   Resource allocation (CPU/Memory).
    *   Revision mode set to 'Multiple' to support canary deployments.
    *   Secrets mounted from Key Vault.

### Azure Resource Diagram (Mermaid)

```mermaid
graph TD
    subgraph "Azure Subscription"
        direction LR
        subgraph "Resource Group (e.g., rg-hackapp-dev-uksouth)"
            ACR[Container Registry]
            KV[Key Vault]
            LAW[Log Analytics Workspace]
            VNet[Virtual Network]

            subgraph VNet
                direction TB
                CAESubnet[CAE Subnet (Delegated)]
            end

            subgraph CAE[Container Apps Environment]
                direction LR
                CA1[Container App: service1]
                CA2[Container App: service2]
                CA1 -- Reads --> KV
                CA2 -- Reads --> KV
                CA1 -- Pulls Image --> ACR
                CA2 -- Pulls Image --> ACR
            end

            CAE -- Uses --> CAESubnet
            CAE -- Sends Logs --> LAW
        end
    end

    User[User/Client] -- HTTPS --> CA1
    CA1 -- Internal HTTP --> CA2

    classDef azure fill:#0078D4,stroke:#000,color:#fff;
    class ACR,KV,LAW,VNet,CAESubnet,CAE,CA1,CA2 azure;
```

## 2. Repository Structure

The repository is organized to separate concerns:

```
.
├── .github/          # GitHub Actions (CI/CD, Reusable Actions)
│   ├── actions/
│   └── workflows/
├── app/              # Application Code & Docker Config
│   ├── service1/
│   ├── service2/
│   └── docker-compose.yml
├── docs/             # Documentation (like this file)
│   ├── architecture.md
│   └── deployment.md
├── infra/            # Terraform Infrastructure as Code
│   ├── modules/      # Reusable Terraform Modules (CAE, CA)
│   ├── env/          # Environment Config (.tfvars)
│   └── *.tf          # Root Terraform files
├── scripts/          # Helper Scripts (OIDC Setup)
├── .dockerignore
├── .gitignore
└── README.md         # Main Project README
```

*   **`.github/`**: Contains all CI/CD logic using GitHub Actions. Reusable actions promote DRY principles.
*   **`app/`**: Holds the source code for each microservice, their respective `Dockerfiles`, and a `docker-compose.yml` for local development.
*   **`docs/`**: Contains markdown documentation.
*   **`infra/`**: Manages all Azure infrastructure using Terraform, with modules for reusability and environment-specific `.tfvars` files.
*   **`scripts/`**: Utility scripts for setup tasks.

## 3. Security Considerations

*   **Authentication:** GitHub Actions authenticate to Azure using OIDC Federation (no stored secrets). Container Apps use Managed Identities to access ACR and Key Vault.
*   **Authorization:** RBAC is used to grant least-privilege access (e.g., `AcrPull` for Container Apps to ACR, `Key Vault Secrets User` for Container Apps to Key Vault, `Contributor` for the GitHub Actions SP over the target resource group).
*   **Secrets Management:** Application secrets are stored in Azure Key Vault. GitHub secrets store Azure credentials for the pipeline.
*   **Network Security:** Container Apps Environment runs within a VNet subnet. Ingress can be configured as internal or external per container app. Network security for the delegated subnet is managed by Azure.
*   **Image Security:** Container images are scanned for vulnerabilities during the CI process using Trivy. Base images are kept minimal, and apps run as non-root users.

## 4. Local Development

Developers can use the `docker-compose.yml` file within the `app/` directory to build and run the multi-container application locally, simulating the deployed environment.