# Azure Container Apps Multi-Container App with CI/CD

This repository provides a template for deploying and managing a multi-container application on Azure Container Apps using Terraform for Infrastructure as Code (IaC) and GitHub Actions for automated CI/CD pipelines. It emphasizes best practices like canary deployments, multi-environment promotion, security, and maintainability, optimized for rapid deployment scenarios like hackathons.

## Features

*   **Infrastructure as Code:** Uses Terraform to define and manage Azure resources predictably.
*   **Multi-Container Deployment:** Supports deploying applications composed of multiple microservices.
*   **Azure Container Apps:** Leverages Azure's serverless container platform.
*   **CI/CD Automation:** Implements GitHub Actions for building, testing, scanning, and deploying the application.
*   **Canary Deployments:** Uses Azure Container Apps' traffic splitting for progressive rollouts (10% -> 50% -> 100%).
*   **Multi-Environment:** Supports distinct `dev` and `prod` environments, easily extensible for others (e.g., staging).
*   **Security Focused:** Implements OIDC federation, managed identities, RBAC, and container scanning.
*   **Local Development:** Includes Docker Compose setup for easy local testing.
*   **Documentation:** Comprehensive setup guides, architecture diagrams, and workflow explanations.

## Repository Structure

```
.
├── .github/          # GitHub Actions workflows and reusable actions
├── app/              # Application source code and Docker configurations
├── docs/             # Documentation (Architecture, Deployment)
├── infra/            # Terraform Infrastructure as Code
├── scripts/          # Helper scripts (e.g., Azure OIDC setup)
├── .dockerignore
├── .gitignore
└── README.md         # This file
```

*(Detailed structure explanation omitted for brevity - see `docs/architecture.md`)*

## Prerequisites

*   [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
*   [Terraform CLI](https://learn.hashicorp.com/tutorials/terraform/install-cli) (v1.x or later)
*   [Docker Desktop](https://www.docker.com/products/docker-desktop)
*   [Git](https://git-scm.com/downloads)
*   An Azure Subscription
*   A GitHub Account

## Setup

1.  **Clone the Repository:**
    ```bash
    git clone <repository-url>
    cd <repository-name>
    ```

2.  **Configure Azure Authentication (OIDC Federation):**
    *   Run the setup script to create the necessary Azure AD Application, Service Principal, and Federated Credentials. This enables passwordless deployment from GitHub Actions.
        ```bash
        ./scripts/setup-azure-oidc.sh <azure-subscription-id> <resource-group-name> <ad-app-name> <github-org>/<github-repo>
        ```
    *   Follow the script's output instructions to configure GitHub secrets (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`).

3.  **Configure GitHub Environments:**
    *   Create `dev` and `prod` environments in your GitHub repository settings (`Settings -> Environments`).
    *   Configure protection rules and required reviewers for the `prod` environment as needed.

4.  **Customize Configuration:**
    *   Update `infra/env/*.tfvars` files with your specific settings (e.g., resource names prefixes, locations).
    *   Modify application code in `app/` as needed.

## Deployment Workflow

1.  **Push to Feature Branch:** Triggers the `CI` workflow (`ci.yml`) - builds, tests, scans containers.
2.  **Merge to `main` Branch:**
    *   Triggers the `CI` workflow again (ensures main is stable).
    *   Triggers the `CD - Dev` workflow (`cd-dev.yml`), which calls the reusable `cd-deploy.yml` to deploy to the `dev` environment.
3.  **Promote to Production:** Manually trigger the `CD - Prod` workflow (`cd-trigger.yml` with `environment: prod`) after successful `dev` validation. This typically requires approval if configured in the environment settings. Deploys to `prod` using canary strategy.

*(See `docs/deployment.md` for a visual representation)*

## Local Development

Use Docker Compose to build and run the containers locally:

```bash
cd app
docker-compose up --build
```

## Contributing

Contributions are welcome! Please follow standard Gitflow practices.

## License

[Specify your license, e.g., MIT License]