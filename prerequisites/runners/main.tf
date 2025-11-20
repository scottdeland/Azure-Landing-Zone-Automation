locals {
  create_network = (
    coalesce(trimspace(tostring(var.virtual_network_name)), "") == "" ||
    coalesce(trimspace(tostring(var.subnet_name)), "") == "" ||
    coalesce(trimspace(tostring(var.vnet_resource_group_name)), "") == ""
  )
}

# Lookup existing subnet only when an existing network is specified
data "azurerm_subnet" "existing" {
  count                = local.create_network ? 0 : 1
  name                 = var.subnet_name
  resource_group_name  = var.vnet_resource_group_name
  virtual_network_name = var.virtual_network_name
}

resource "azurerm_resource_group" "resource_group" {
  name     = "rg-${var.runner_name}"
  location = var.location
}

# Create VNet/Subnet only when a network was not provided
resource "azurerm_virtual_network" "virtual_network" {
  count               = local.create_network ? 1 : 0
  name                = "vnet-${var.runner_name}"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  address_space       = var.vnet_address_space
}

resource "azurerm_subnet" "this" {
  count                = local.create_network ? 1 : 0
  name                 = "snet-${var.runner_name}"
  resource_group_name  = azurerm_resource_group.resource_group.name
  virtual_network_name = azurerm_virtual_network.virtual_network[0].name
  address_prefixes     = var.subnet_address_prefixes

  delegation {
    name = "aca-delegation"
    service_delegation {
      name = "Microsoft.App/environments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
    }
  }
}

locals {
  subnet_id = local.create_network ? azurerm_subnet.this[0].id : data.azurerm_subnet.existing[0].id
}

resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = "law-${var.runner_name}"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_app_environment" "container_app_environment" {
  name                               = var.runner_name
  location                           = azurerm_resource_group.resource_group.location
  resource_group_name                = azurerm_resource_group.resource_group.name
  infrastructure_subnet_id           = local.subnet_id
  log_analytics_workspace_id         = azurerm_log_analytics_workspace.log_analytics_workspace.id
  infrastructure_resource_group_name = "dev-${var.runner_name}-${var.runner_name}-${var.location}"

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
    maximum_count         = 2
    minimum_count         = 1
  }
}

resource "azurerm_container_app_job" "container_app_job" {
  name                         = "${var.runner_name}-job"
  location                     = azurerm_resource_group.resource_group.location
  resource_group_name          = azurerm_resource_group.resource_group.name
  container_app_environment_id = azurerm_container_app_environment.container_app_environment.id
  replica_timeout_in_seconds   = 1800
  replica_retry_limit          = 0
  workload_profile_name        = "Consumption"

  identity {
    type = "SystemAssigned"
  }

  template {
    container {
      name   = "gh-runner"
      image  = var.container_image
      cpu    = "2.0"
      memory = "4Gi"
      env {
        name        = "GITHUB_PAT"
        secret_name = "personal-access-token"
      }
      env {
        name  = "GH_URL"
        value = "https://github.com/${var.owner}/${var.repo}"
      }
      env {
        name  = "REGISTRATION_TOKEN_API_URL"
        value = "https://api.github.com/repos/${var.owner}/${var.repo}/actions/runners/registration-token"
      }
      // Needed to fix MSI issue https://github.com/microsoft/azure-container-apps/issues/502
      env {
        name = "APPSETTING_WEBSITE_SITE_NAME"
        value = "azcli-workaround"
      }
    }
  }
  secret {
    name  = "personal-access-token"
    value = var.github_pat
  }
  event_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
    scale {
      min_executions              = 0
      max_executions              = 10
      polling_interval_in_seconds = 5
      rules {
        name             = "github-runner"
        custom_rule_type = "github-runner"
        metadata = {
          githubAPIURL              = "https://api.github.com"
          owner                     = var.owner
          runnerScope               = "repo"
          repos                     = var.repo
          targetWorkflowQueueLength = "1"
        }
        authentication {
          secret_name       = "personal-access-token"
          trigger_parameter = "personalAccessToken"
        }
      }
    }
  }
}
