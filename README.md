# Azure Landing Zone Automation

This repository provides automation for deploying and operating Azure Landing Zones, along with the prerequisites these solutions depend on. It is intended as a practical, modular collection you can adopt selectively or end‑to‑end.

We will continue to iterate on this README as new solutions, patterns, and guidance are added.

**What’s here**
- Landing zone implementations (Terraform) for common scenarios such as AKS, AVD, Palo Alto, and base/shared resources.
- Prerequisites and enablement scripts, including:
  - OIDC setup for GitHub Actions to authenticate to Azure without long‑lived secrets.
  - Staging GitHub runners and related infrastructure.

**Repo structure (high level)**
- `landing-zones/` – Terraform configurations for specific landing zones (e.g., `aks`, `avd`, `palo-alto`, `base`).
- `prerequisites/` – Scripts and Terraform for foundational setup (e.g., `oidc`, `staging-runners`).
- `.github/workflows/` – CI/CD workflows for testing and provisioning.

**Getting started**
- Review the `prerequisites/` folder first (OIDC setup and any required infra).
- Choose a landing zone under `landing-zones/` and follow its local `readme.md` for inputs and deployment steps.

**Contributing and iterations**
- Please open issues and PRs to propose improvements or new landing zone modules.
- Expect iterative updates to documentation and patterns as more solutions are added.
