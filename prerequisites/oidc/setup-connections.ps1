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
$federatedPath = "/v1.0/applications/$($application.Id)/federatedIdentityCredentials"
$existingResponse = Invoke-AzRestMethod -Method GET -Path $federatedPath
$existingCredentials = @()
if ($existingResponse.Content) {
    $existingCredentials = (ConvertFrom-Json -InputObject $existingResponse.Content).value
}

$existing = $existingCredentials | Where-Object { $_.name -eq $CredentialName } | Select-Object -First 1

if ($existing) {
    Invoke-AzRestMethod -Method PATCH -Path "$federatedPath/$($existing.id)" -Payload $jsonBody | Out-Null
    $action = "updated"
}
else {
    Invoke-AzRestMethod -Method POST -Path $federatedPath -Payload $jsonBody | Out-Null
    $action = "created"
}

Write-Host "OIDC federated credential $action successfully." -ForegroundColor Green
Write-Host "TenantId      : $TenantId"
Write-Host "ClientId      : $($application.AppId)"
Write-Host "App Object Id : $($application.Id)"
Write-Host "Credential    : $CredentialName"
Write-Host "Subject       : $subject"
