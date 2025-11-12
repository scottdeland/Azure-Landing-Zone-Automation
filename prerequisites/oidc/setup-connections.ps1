[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ApplicationDisplayName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$GitHubOrganization,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$GitHubRepository,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GitHubBranch = "main",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GitHubEnvironment,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$CredentialName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Description = "GitHub Actions Terraform OIDC connection"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$requiredModules = @("Az.Accounts", "Az.Resources")
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        throw "PowerShell module '$module' is required. Install with 'Install-Module $module'."
    }

    Import-Module $module -ErrorAction Stop | Out-Null
}

$context = Get-AzContext -ErrorAction SilentlyContinue
$needsReconnect = -not $context

if (-not $TenantId -and $context) {
    $TenantId = $context.Tenant.Id
}

if (-not $SubscriptionId -and $context) {
    $SubscriptionId = $context.Subscription.Id
}

if ($TenantId -and $context -and ($context.Tenant.Id -ne $TenantId)) {
    $needsReconnect = $true
}

if ($SubscriptionId -and $context -and ($context.Subscription.Id -ne $SubscriptionId)) {
    $needsReconnect = $true
}

if ($needsReconnect) {
    $connectParams = @{}
    if ($TenantId) {
        $connectParams["Tenant"] = $TenantId
    }
    if ($SubscriptionId) {
        $connectParams["Subscription"] = $SubscriptionId
    }

    Connect-AzAccount @connectParams | Out-Null
    $context = Get-AzContext
}

if (-not $TenantId) {
    $TenantId = $context.Tenant.Id
}

if ($SubscriptionId -and ($context.Subscription.Id -ne $SubscriptionId)) {
    Set-AzContext -Subscription $SubscriptionId | Out-Null
    $context = Get-AzContext
}

if (-not $PSBoundParameters.ContainsKey("CredentialName")) {
    if ($GitHubEnvironment) {
        $CredentialName = "github-env-$($GitHubEnvironment.ToLowerInvariant())-oidc"
    }
    else {
        $normalizedBranch = $GitHubBranch.Replace("/", "-").ToLowerInvariant()
        $CredentialName = "github-branch-$normalizedBranch-oidc"
    }
}

$application = Get-AzADApplication -DisplayName $ApplicationDisplayName -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $application) {
    $application = New-AzADApplication -DisplayName $ApplicationDisplayName -SignInAudience AzureADMyOrg
}

$servicePrincipal = Get-AzADServicePrincipal -ApplicationId $application.AppId -ErrorAction SilentlyContinue
if (-not $servicePrincipal) {
    $servicePrincipal = New-AzADServicePrincipal -ApplicationId $application.AppId
}

# Ensure the service principal has Contributor on the target subscription
try {
    if (-not $SubscriptionId) {
        $SubscriptionId = (Get-AzContext).Subscription.Id
    }

    $scope = "/subscriptions/$SubscriptionId"

    $existingAssignment = Get-AzRoleAssignment -ObjectId $servicePrincipal.Id -Scope $scope -RoleDefinitionName "Contributor" -ErrorAction SilentlyContinue
    if (-not $existingAssignment) {
        Write-Host "Assigning 'Contributor' role to the service principal at scope $scope..." -ForegroundColor Cyan
        New-AzRoleAssignment -ObjectId $servicePrincipal.Id -Scope $scope -RoleDefinitionName "Contributor" | Out-Null
        Write-Host "Contributor role assignment created." -ForegroundColor Green
    }
    else {
        Write-Host "'Contributor' role already assigned at scope $scope." -ForegroundColor Yellow
    }
}
catch {
    Write-Warning ("Failed to ensure 'Contributor' role assignment: {0}" -f $_.Exception.Message)
}

$subject = if ($GitHubEnvironment) {
    "repo:$GitHubOrganization/$GitHubRepository:environment:$GitHubEnvironment"
}
else {
    "repo:$GitHubOrganization/$GitHubRepository:ref:refs/heads/$GitHubBranch"
}

$body = @{
    name        = $CredentialName
    issuer      = "https://token.actions.githubusercontent.com"
    subject     = $subject
    description = $Description
    audiences   = @("api://AzureADTokenExchange")
}

$jsonBody = $body | ConvertTo-Json -Depth 4

# Use Microsoft Graph with a full URI to avoid ARM path ambiguity
$graphBase = "https://graph.microsoft.com/v1.0"
$federatedUri = "$graphBase/applications/$($application.Id)/federatedIdentityCredentials"

# Retrieve existing federated credentials safely
$existingCredentials = @()
try {
    $existingResponse = Invoke-AzRestMethod -Method GET -Uri $federatedUri -ErrorAction Stop
    if ($existingResponse -and $existingResponse.Content) {
        $parsed = $existingResponse.Content | ConvertFrom-Json
        if ($null -ne $parsed) {
            if ($parsed.PSObject.Properties.Name -contains 'value') {
                $existingCredentials = $parsed.value
            }
            elseif ($parsed.PSObject.Properties.Name -contains 'id') {
                $existingCredentials = @($parsed)
            }
        }
    }
}
catch {
    Write-Verbose ("Failed to query existing federated credentials: {0}" -f $_.Exception.Message)
}

$existing = $existingCredentials | Where-Object { $_.name -eq $CredentialName } | Select-Object -First 1

try {
    if ($existing) {
        Invoke-AzRestMethod -Method PATCH -Uri ("{0}/{1}" -f $federatedUri, $existing.id) -Payload $jsonBody | Out-Null
        $action = "updated"
    }
    else {
        Invoke-AzRestMethod -Method POST -Uri $federatedUri -Payload $jsonBody | Out-Null
        $action = "created"
    }
}
catch {
    throw "Failed to $action federated identity credential: $($_.Exception.Message)"
}

Write-Host "OIDC federated credential $action successfully." -ForegroundColor Green
Write-Host "TenantId      : $TenantId"
Write-Host "ClientId      : $($application.AppId)"
Write-Host "App Object Id : $($application.Id)"
Write-Host "Credential    : $CredentialName"
Write-Host "Subject       : $subject"

# --
# Additionally create a client secret and emit the AZURE_CREDENTIALS JSON
# for use with azure/login@v2 'creds' input in GitHub Actions.
# This keeps OIDC (federated credential) in place while also enabling
# secret-based login to match the current workflow format.

try {
    $hasAzCli = Get-Command az -ErrorAction SilentlyContinue
    if (-not $SubscriptionId) {
        $SubscriptionId = (Get-AzContext).Subscription.Id
    }

    $secretLabel = "${CredentialName}-sp-secret"
    $credsJson = $null
    $secretValue = $null

    $cliUsable = $false
    if ($hasAzCli) {
        # Verify Azure CLI is logged in
        $null = az account show --only-show-errors --output none 2>$null
        if ($LASTEXITCODE -eq 0) { $cliUsable = $true }
    }

    if ($cliUsable) {
        Write-Host "\nCreating/rotating application client secret via Azure CLI..." -ForegroundColor Cyan
        $resetArgs = @(
            'ad','app','credential','reset',
            '--id', $application.AppId,
            '--display-name', $secretLabel,
            '--years','2',
            '--append',
            '--only-show-errors',
            '--output','json'
        )
        $secretResultJson = az @resetArgs 2>$null
        if ($LASTEXITCODE -eq 0 -and $secretResultJson) {
            $secretResult = $secretResultJson | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($secretResult -and $secretResult.password) {
                $secretValue = $secretResult.password
            }
        }
        else {
            Write-Verbose "Azure CLI credential reset did not return JSON or exited non-zero; will attempt Graph fallback."
        }
    }

    if (-not $secretValue) {
        Write-Host "\nFalling back to Microsoft Graph addPassword..." -ForegroundColor Cyan
        $graphBase = "https://graph.microsoft.com/v1.0"
        $addPwdUri = "$graphBase/applications/$($application.Id)/addPassword"
        $end = (Get-Date).AddYears(2).ToUniversalTime().ToString("o")
        $pwdReq = @{ passwordCredential = @{ displayName = $secretLabel; endDateTime = $end } } | ConvertTo-Json -Depth 5
        $pwdResp = Invoke-AzRestMethod -Method POST -Uri $addPwdUri -Payload $pwdReq -ErrorAction Stop
        if ($pwdResp -and $pwdResp.Content) {
            $pwdObj = $pwdResp.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
            # Graph returns 'secretText' with the generated secret
            if ($pwdObj -and $pwdObj.secretText) { $secretValue = $pwdObj.secretText }
        }
        if (-not $secretValue) {
            throw "Microsoft Graph did not return a secretText for the new password credential."
        }
    }

    $creds = [ordered]@{
        clientId       = $application.AppId
        clientSecret   = $secretValue
        tenantId       = $TenantId
        subscriptionId = $SubscriptionId
    }
    $credsJson = ($creds | ConvertTo-Json -Compress)

    Write-Host "\nAZURE_CREDENTIALS secret value (copy exactly to your GitHub secret):" -ForegroundColor Yellow
    Write-Host $credsJson

    Write-Host "\nNext steps:" -ForegroundColor Cyan
    Write-Host "- In GitHub, navigate to Settings -> Secrets and variables -> Actions -> New repository secret"
    Write-Host "- Name: AZURE_CREDENTIALS"
    Write-Host "- Value: Paste the JSON above"

    $hasGh = Get-Command gh -ErrorAction SilentlyContinue
    if ($hasGh -and $GitHubOrganization -and $GitHubRepository) {
        $repoRef = "$GitHubOrganization/$GitHubRepository"
        Write-Host "\nGitHub CLI alternative (if authenticated):" -ForegroundColor DarkCyan
        Write-Host ("gh secret set AZURE_CREDENTIALS --repo {0} --body '{1}'" -f $repoRef, $credsJson)
    }
}
catch {
    Write-Warning ("Failed to create or emit AZURE_CREDENTIALS secret: {0}" -f $_.Exception.Message)
    Write-Host "To generate the AZURE_CREDENTIALS secret manually with Azure CLI:" -ForegroundColor Cyan
    Write-Host ("- Create/rotate secret: az ad app credential reset --id {0} --display-name {1}-sp-secret --years 2 --append --only-show-errors --output json" -f $application.AppId, $CredentialName)
    Write-Host "- Capture the output 'password' value and construct this JSON:"
    Write-Host "  {\"clientId\":\"$($application.AppId)\",\"clientSecret\":\"<password>\",\"tenantId\":\"$TenantId\",\"subscriptionId\":\"$SubscriptionId\"}"
    Write-Host "- Add it to GitHub as the 'AZURE_CREDENTIALS' Actions secret"
}
