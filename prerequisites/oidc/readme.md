# OIDC Setup for GitHub Actions (setup-connections.ps1)

This folder contains `setup-connections.ps1`, a helper script to configure Azure Entra ID (Azure AD) for GitHub Actions using OpenID Connect (OIDC) and to optionally generate the `AZURE_CREDENTIALS` JSON used by the existing GitHub workflow login step.

What the script does:

- Ensures an Entra ID Application and corresponding Service Principal exist for the provided display name.
- Creates or updates a Federated Identity Credential on the Application for GitHub Actions OIDC (via Microsoft Graph):
  - Issuer: `https://token.actions.githubusercontent.com`
  - Audience: `api://AzureADTokenExchange`
  - Subject: based on repository + branch or repository + environment.
- Ensures the Service Principal has the `Contributor` role at the specified subscription scope (idempotent). If you lack permissions, the script logs a warning and continues.
- Optionally creates/rotates a client secret and prints the exact `AZURE_CREDENTIALS` JSON to copy into your GitHub repository secret. It first attempts Azure CLI and, if unavailable or unsuccessful, falls back to Microsoft Graph `addPassword`. This allows you to keep using the workflow input `creds: ${{ secrets.AZURE_CREDENTIALS }}`.

## Prerequisites

- PowerShell 7+ recommended.
- PowerShell modules (recent versions):
  - `Az.Accounts`
  - `Az.Resources`
- The script uses Microsoft Graph via `Invoke-AzRestMethod -Uri` to manage federated identity credentials and, if needed, to create a client secret; ensure your `Az` modules are reasonably up to date. You can check with:
  
  ```powershell
  Get-Module Az.Accounts -ListAvailable | Select-Object Name,Version | Sort-Object Version -Descending | Select-Object -First 1
  ```
- Azure login with permissions to register applications and create service principals in Entra ID, and to read the target subscription.
- Role assignment permissions on the target subscription (Owner or User Access Administrator) if you want the script to successfully assign `Contributor` to the Service Principal.
- Azure CLI (`az`) installed and logged in if you want the script to automatically create/rotate the client secret. If `az` is not available or fails, the script falls back to Microsoft Graph `addPassword`.
- (Optional) GitHub CLI (`gh`) if you want a convenience command to set the secret from your terminal.

Required permissions (one of the following):
- Directory role: Application Administrator (or higher) to create/update app credentials and federated identity credentials.
- Or an app/token with Microsoft Graph permissions like `Application.ReadWrite.All` and admin consent.

## Login

You can either pre-connect in PowerShell or let the script prompt you:

```powershell
# Recommended: connect first and select the right tenant/subscription
Connect-AzAccount -Tenant <tenantId> -Subscription <subscriptionId>
```

Alternatively, pass `-TenantId` and `-SubscriptionId` to the script; it will connect or switch context as needed.

## Parameters

- `-ApplicationDisplayName` (string, required)
  - Display name of the Entra ID Application. If it doesn’t exist, the script creates it.
- `-GitHubOrganization` (string, required)
  - GitHub organization or user that owns the repository.
- `-GitHubRepository` (string, required)
  - Repository name (without the org). Example: `my-repo`.
- `-GitHubBranch` (string, optional, default: `main`)
  - Branch used to build the OIDC subject when no environment is provided. Subject format: `repo:<org>/<repo>:ref:refs/heads/<branch>`.
- `-GitHubEnvironment` (string, optional)
  - If provided, the OIDC subject uses the environment instead of a branch. Subject format: `repo:<org>/<repo>:environment:<environment>`.
- `-CredentialName` (string, optional)
  - Name of the federated credential. Defaults to:
    - `github-env-<environment>-oidc` when `-GitHubEnvironment` is provided
    - `github-branch-<branch>-oidc` otherwise (branch is normalized)
- `-TenantId` (string, optional)
  - Entra ID tenant ID. If omitted, the current Az context tenant is used.
- `-SubscriptionId` (string, optional)
  - Azure subscription ID. If omitted, the current Az context subscription is used.
- `-Description` (string, optional, default: `GitHub Actions Terraform OIDC connection`)
  - Description applied to the federated credential.

## What It Creates/Updates

- Entra ID Application with display name you specify (creates if missing).
- Service Principal for the application (creates if missing).
- Federated Identity Credential bound to your GitHub repo branch or environment.
- A `Contributor` role assignment for the Service Principal at the subscription scope (if not already present).
- Optionally, a client secret credential for the application (via Azure CLI) and the `AZURE_CREDENTIALS` JSON.

## Usage Examples

Branch-based subject (default):

```powershell
./setup-connections.ps1 \
  -ApplicationDisplayName "my-gh-terraform-app" \
  -GitHubOrganization "my-org" \
  -GitHubRepository "my-repo" \
  -GitHubBranch "main" \
  -TenantId "<tenant-guid>" \
  -SubscriptionId "<subscription-guid>"
```

Environment-based subject:

```powershell
./setup-connections.ps1 \
  -ApplicationDisplayName "my-gh-terraform-app" \
  -GitHubOrganization "my-org" \
  -GitHubRepository "my-repo" \
  -GitHubEnvironment "prod" \
  -TenantId "<tenant-guid>" \
  -SubscriptionId "<subscription-guid>"
```

## Output and GitHub Secret

On success, the script prints the key details (TenantId, ClientId, App Object Id, Credential name, Subject) and the `AZURE_CREDENTIALS` JSON in this shape (generated via Azure CLI or Graph fallback):

```json
{"clientId":"<GUID>","clientSecret":"<SECRET>","tenantId":"<GUID>","subscriptionId":"<GUID>"}
```

Add this as a GitHub Actions secret:

1. In GitHub, go to: Settings → Secrets and variables → Actions → New repository secret
2. Name: `AZURE_CREDENTIALS`
3. Value: paste the JSON from the script

Optional using GitHub CLI (if authenticated):

```bash
gh secret set AZURE_CREDENTIALS --repo <org>/<repo> --body '{"clientId":"<GUID>","clientSecret":"<SECRET>","tenantId":"<GUID>","subscriptionId":"<GUID>"}'
```

## Notes

- Your existing workflow can continue using:
  
  ```yaml
  - uses: azure/login@v2
    with:
      creds: ${{ secrets.AZURE_CREDENTIALS }}
      allow-no-subscriptions: true
      audience: 'api://AzureADTokenExchange'
  ```

- Later, you can switch to pure OIDC (no client secret) by changing the workflow to use `client-id`, `tenant-id`, and `subscription-id` inputs and removing `creds`.
- The script now attempts to ensure the Service Principal has `Contributor` on the subscription; if it cannot (insufficient rights), assign roles manually.

## Troubleshooting

- Warning: `Azure CLI did not return a secret credential response.`
  - The script will attempt a Graph fallback (`addPassword`) automatically. If both paths fail, verify:
    - Azure CLI is installed and logged in (`az account show`).
    - Your account has permission to manage app credentials (Application Administrator or equivalent).
    - Az modules are up to date enough to call Microsoft Graph via `Invoke-AzRestMethod -Uri`.
- Error when listing federated credentials or patching/creating them:
  - Ensure your context/permissions allow Microsoft Graph application reads/writes.
  - Re-run after `Connect-AzAccount -Tenant <tenantId> -Subscription <subscriptionId>`.
 - Warning: `Failed to ensure 'Contributor' role assignment: ...`
   - Your account likely lacks subscription-level permissions (Owner/User Access Administrator). Either rerun with sufficient rights or assign the role manually:
     ```bash
     az role assignment create \
       --assignee-object-id <sp-object-id> \
       --assignee-principal-type ServicePrincipal \
       --role Contributor \
       --scope /subscriptions/<subscription-id>
     ```
