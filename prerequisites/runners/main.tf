locals {
  create_network = (
    var.virtual_network_name == null || trimspace(var.virtual_network_name) == "" ||
    var.subnet_name == null || trimspace(var.subnet_name) == "" ||
    var.vnet_resource_group_name == null || trimspace(var.vnet_resource_group_name) == ""
  )
}

module "naming" {
  source = "../../modules/terraform-azurerm-naming"
  suffix = [var.runner_name]
}

locals {
  managed_vnet_name   = module.naming.virtual_network.name
  managed_subnet_name = module.naming.subnet.name
}

data "azurerm_client_config" "current" {}

# Explicitly register Microsoft.App to avoid 409 during ACA creation
resource "azapi_resource_action" "register_microsoft_app" {
  type        = "Microsoft.App@2022-03-01"
  resource_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.App"
  action      = "register"
  method      = "POST"
}

# Lookup existing subnet only when an existing network is specified
data "azurerm_subnet" "existing" {
  count                = local.create_network ? 0 : 1
  name                 = var.subnet_name
  resource_group_name  = var.vnet_resource_group_name
  virtual_network_name = var.virtual_network_name
}

resource "azurerm_resource_group" "resource_group" {
  name     = module.naming.resource_group.name
  location = var.location
}

# Create VNet/Subnet only when a network was not provided
module "runner_virtual_network" {
  count   = local.create_network ? 1 : 0
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.16.0"

  enable_telemetry = false

  name          = local.managed_vnet_name
  location      = azurerm_resource_group.resource_group.location
  parent_id     = azurerm_resource_group.resource_group.id
  address_space = var.vnet_address_space

  subnets = {
    "${local.managed_subnet_name}" = {
      name             = local.managed_subnet_name
      address_prefixes = var.subnet_address_prefixes
      delegations = [{
        name = "aca-delegation"
        service_delegation = {
          name = "Microsoft.App/environments"
        }
      }]
    }
  }
}

locals {
  subnet_id = local.create_network ? module.runner_virtual_network[0].subnets[local.managed_subnet_name].resource_id : data.azurerm_subnet.existing[0].id
}

resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = module.naming.log_analytics_workspace.name
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_app_environment" "container_app_environment" {
  name                               = module.naming.container_app_environment.name
  location                           = azurerm_resource_group.resource_group.location
  resource_group_name                = azurerm_resource_group.resource_group.name
  infrastructure_subnet_id           = local.subnet_id
  log_analytics_workspace_id         = azurerm_log_analytics_workspace.log_analytics_workspace.id
  infrastructure_resource_group_name = "dev-${var.runner_name}-${var.runner_name}-${var.location}"
  internal_load_balancer_enabled     = true
  depends_on                         = [azapi_resource_action.register_microsoft_app]

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
    maximum_count         = 2
    minimum_count         = 1
  }
}

resource "azurerm_container_app_job" "container_app_job" {
  name                         = "${module.naming.container_app.name}-job"
  location                     = azurerm_resource_group.resource_group.location
  resource_group_name          = azurerm_resource_group.resource_group.name
  container_app_environment_id = azurerm_container_app_environment.container_app_environment.id
  replica_timeout_in_seconds   = 3600
  replica_retry_limit          = 0
  workload_profile_name        = "Consumption"

  identity {
    type = "SystemAssigned"
  }

  registry {
    server               = "ghcr.io"
    username             = var.owner
    password_secret_name = "personal-access-token"
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
        name  = "APPSETTING_WEBSITE_SITE_NAME"
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
