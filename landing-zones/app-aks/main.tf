module "naming" {
  source = "../../modules/terraform-azurerm-naming"
  suffix = [var.name_prefix, var.environment, var.location_short]
}

data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

data "azurerm_virtual_network" "ghinfra" {
  name                = var.ghinfra_vnet_name
  resource_group_name = var.ghinfra_resource_group_name
}

resource "random_password" "postgres_admin" {
  length           = 24
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "_%@"
  special          = true
}

module "resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.2.2"

  enable_telemetry = false
  name             = module.naming.resource_group.name
  location         = var.location
  tags             = local.tags
}

module "log_analytics_workspace" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "0.5.1"

  enable_telemetry = false
  name             = module.naming.log_analytics_workspace.name
  location         = var.location
  resource_group_name = module.resource_group.name
  log_analytics_workspace_sku = "PerGB2018"
  log_analytics_workspace_retention_in_days = 30
  tags             = local.tags
}

data "azurerm_log_analytics_workspace" "solution" {
  name                = module.naming.log_analytics_workspace.name
  resource_group_name = module.resource_group.name
  depends_on          = [module.log_analytics_workspace]
}

resource "azurerm_monitor_action_group" "alerts" {
  count               = local.alerts_enabled ? 1 : 0
  name                = module.naming.monitor_action_group.name
  resource_group_name = module.resource_group.name
  short_name          = substr(module.naming.monitor_action_group.name, 0, 12)
  tags                = local.tags

  dynamic "email_receiver" {
    for_each = toset(var.alert_email_receivers)
    content {
      name          = "email-${substr(md5(email_receiver.value), 0, 6)}"
      email_address = email_receiver.value
    }
  }
}

resource "random_uuid" "workbook" {}

resource "azurerm_application_insights_workbook" "app_aks_overview" {
  name                = random_uuid.workbook.result
  resource_group_name = module.resource_group.name
  location            = var.location
  display_name        = "App-AKS Overview"
  source_id           = lower(module.log_analytics_workspace.resource_id)
  tags                = local.tags

  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type = 1
        name = "title"
        content = {
          json = "# App-AKS Overview\nThis workbook is scoped to the landing zone Log Analytics workspace."
        }
      }
    ]
  })
}

module "application_insights" {
  source  = "Azure/avm-res-insights-component/azurerm"
  version = "0.2.0"

  enable_telemetry = false
  name             = module.naming.application_insights.name
  location         = var.location
  resource_group_name = module.resource_group.name
  application_type = "web"
  workspace_id     = module.log_analytics_workspace.resource_id
  tags             = local.tags
}

resource "azurerm_monitor_diagnostic_setting" "subscription_activity_log" {
  name                       = "diag-activity-log"
  target_resource_id         = data.azurerm_subscription.current.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_log {
    category = "Administrative"
  }
  enabled_log {
    category = "Security"
  }
  enabled_log {
    category = "ServiceHealth"
  }
  enabled_log {
    category = "Alert"
  }
  enabled_log {
    category = "Recommendation"
  }
  enabled_log {
    category = "Policy"
  }
  enabled_log {
    category = "Autoscale"
  }
  enabled_log {
    category = "ResourceHealth"
  }
}

resource "azurerm_monitor_metric_alert" "app_service_plan_cpu" {
  count               = local.alerts_enabled ? 1 : 0
  name                = "alert-${module.naming.app_service_plan.name}-cpu"
  resource_group_name = module.resource_group.name
  scopes              = [module.app_service_plan.resource_id]
  description         = "App Service Plan CPU > 80% for 5 minutes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/serverFarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.alerts[0].id
  }
}

resource "azurerm_monitor_metric_alert" "web_app_http_5xx" {
  for_each            = local.alerts_enabled ? { frontend = module.web_app_frontend.resource_id, backend = module.web_app_backend.resource_id } : {}
  name                = "alert-${local.app_service_names[each.key]}-http5xx"
  resource_group_name = module.resource_group.name
  scopes              = [each.value]
  description         = "HTTP 5xx responses detected on the web app."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5
  }

  action {
    action_group_id = azurerm_monitor_action_group.alerts[0].id
  }
}

// SQL DTU alert removed with PostgreSQL migration.

module "apim_nsg" {
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "0.5.1"

  enable_telemetry = false
  name             = local.apim_nsg_name
  location         = var.location
  resource_group_name = module.resource_group.name
  tags             = local.tags
  security_rules = {
    allow_appgw_https = {
      name                        = "${module.naming.network_security_group_rule.name}-apim-allow-appgw"
      priority                    = 100
      direction                   = "Inbound"
      access                      = "Allow"
      protocol                    = "Tcp"
      source_port_range           = "*"
      destination_port_ranges     = ["443", "80"]
      source_address_prefix       = var.subnet_cidrs.app_gateway
      destination_address_prefix  = var.subnet_cidrs.apim
    }
    deny_vnet_http_https = {
      name                        = "${module.naming.network_security_group_rule.name}-apim-deny-vnet"
      priority                    = 200
      direction                   = "Inbound"
      access                      = "Deny"
      protocol                    = "Tcp"
      source_port_range           = "*"
      destination_port_ranges     = ["443", "80"]
      source_address_prefix       = "VirtualNetwork"
      destination_address_prefix  = var.subnet_cidrs.apim
    }
  }
}

data "azurerm_network_watcher" "current" {
  name                = "NetworkWatcher_${lower(replace(var.location, " ", ""))}"
  resource_group_name = "NetworkWatcherRG"
}

module "network_watcher" {
  source  = "Azure/avm-res-network-networkwatcher/azurerm"
  version = "0.3.2"

  enable_telemetry     = false
  network_watcher_id   = data.azurerm_network_watcher.current.id
  network_watcher_name = data.azurerm_network_watcher.current.name
  resource_group_name  = data.azurerm_network_watcher.current.resource_group_name
  location             = data.azurerm_network_watcher.current.location

  flow_logs = var.enable_nsg_flow_logs ? {
    apim_nsg = {
      name                      = "flow-${local.apim_nsg_name}"
      network_security_group_id = module.apim_nsg.resource_id
      storage_account_id        = module.storage_account_nsg_logs.resource_id
      enabled                   = true

      retention_policy = {
        enabled = true
        days    = 30
      }

      traffic_analytics = {
        enabled               = true
        workspace_id          = data.azurerm_log_analytics_workspace.solution.workspace_id
        workspace_region      = lower(replace(var.location, " ", ""))
        workspace_resource_id = module.log_analytics_workspace.resource_id
        interval_in_minutes   = 60
      }
      target_resource_id = module.apim_nsg.resource_id
    }
  } : {}
}

module "nat_gateway" {
  source  = "Azure/avm-res-network-natgateway/azurerm"
  version = "0.2.1"

  enable_telemetry = false
  name             = module.naming.nat_gateway.name
  location         = var.location
  resource_group_name = module.resource_group.name
  tags             = local.tags

  public_ip_configuration = {
    allocation_method = "Static"
    sku               = "Standard"
  }

  public_ips = {
    primary = {
      name = "pip-${module.naming.nat_gateway.name}"
    }
  }
}

module "virtual_network" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.17.1"

  enable_telemetry = false
  name             = module.naming.virtual_network.name
  location         = var.location
  parent_id        = module.resource_group.resource_id
  address_space    = [var.vnet_cidr]
  tags             = local.tags
  diagnostic_settings = local.aks_diagnostic_settings

  subnets = {
    "${local.subnet_names.app_gateway}" = {
      name             = local.subnet_names.app_gateway
      address_prefixes = [var.subnet_cidrs.app_gateway]
    }
    "${local.subnet_names.aks}" = {
      name             = local.subnet_names.aks
      address_prefixes = [var.subnet_cidrs.aks]
      nat_gateway = {
        id = module.nat_gateway.resource_id
      }
    }
    "${local.subnet_names.appsvc_integration}" = {
      name             = local.subnet_names.appsvc_integration
      address_prefixes = [var.subnet_cidrs.appsvc_integration]
      delegations = [{
        name = "appsvc-integration"
        service_delegation = {
          name = "Microsoft.Web/serverFarms"
        }
      }]
    }
    "${local.subnet_names.private_endpoints}" = {
      name             = local.subnet_names.private_endpoints
      address_prefixes = [var.subnet_cidrs.private_endpoints]
      private_endpoint_network_policies = "Disabled"
    }
    "${local.subnet_names.apim}" = {
      name             = local.subnet_names.apim
      address_prefixes = [var.subnet_cidrs.apim]
      network_security_group = {
        id = module.apim_nsg.resource_id
      }
    }
  }
}

resource "azurerm_virtual_network_peering" "app_to_ghinfra" {
  name                      = "peer-${module.naming.virtual_network.name}-to-${var.ghinfra_vnet_name}"
  resource_group_name       = module.resource_group.name
  virtual_network_name      = module.naming.virtual_network.name
  remote_virtual_network_id = data.azurerm_virtual_network.ghinfra.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
  depends_on = [module.virtual_network]
}

resource "azurerm_virtual_network_peering" "ghinfra_to_app" {
  name                      = "peer-${var.ghinfra_vnet_name}-to-${module.naming.virtual_network.name}"
  resource_group_name       = data.azurerm_virtual_network.ghinfra.resource_group_name
  virtual_network_name      = data.azurerm_virtual_network.ghinfra.name
  remote_virtual_network_id = module.virtual_network.resource_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
  depends_on = [module.virtual_network]
}

module "private_dns_zone" {
  for_each = local.private_dns_zones

  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.4.4"

  enable_telemetry = false
  domain_name      = each.key
  parent_id        = module.resource_group.resource_id
  tags             = local.tags

  virtual_network_links = {
    "vnet-link" = {
      name               = "pdnslink-${replace(each.key, ".", "-")}"
      virtual_network_id = module.virtual_network.resource_id
      registration_enabled = false
    }
    "ghinfra-link" = {
      name               = "pdnslink-ghinfra-${replace(each.key, ".", "-")}"
      virtual_network_id = data.azurerm_virtual_network.ghinfra.id
      registration_enabled = false
    }
  }
}

module "aks_private_dns_zone" {
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.4.4"

  enable_telemetry = false
  domain_name      = local.aks_private_dns_zone_name
  parent_id        = module.resource_group.resource_id
  tags             = local.tags

  virtual_network_links = {
    "vnet-link" = {
      name                  = "pdnslink-${replace(local.aks_private_dns_zone_name, ".", "-")}"
      virtual_network_id    = module.virtual_network.resource_id
      registration_enabled  = false
    }
    "ghinfra-link" = {
      name                  = "pdnslink-ghinfra-${replace(local.aks_private_dns_zone_name, ".", "-")}"
      virtual_network_id    = data.azurerm_virtual_network.ghinfra.id
      registration_enabled  = false
    }
  }
}

module "aks" {
  source  = "Azure/avm-res-containerservice-managedcluster/azurerm"
  version = "0.4.2"

  enable_telemetry = false
  name             = module.naming.kubernetes_cluster.name
  location         = var.location
  parent_id        = module.resource_group.resource_id
  tags             = local.tags
  dns_prefix       = module.naming.kubernetes_cluster.name

  managed_identities = {
    system_assigned = true
  }

  api_server_access_profile = {
    enable_private_cluster             = true
    enable_private_cluster_public_fqdn = false
  }
  public_network_access = "Disabled"
  network_profile = {
    outbound_type = "userAssignedNATGateway"
  }
  diagnostic_settings = local.diagnostic_settings
  addon_profile_oms_agent = {
    enabled = true
    config = {
      log_analytics_workspace_resource_id = module.log_analytics_workspace.resource_id
    }
  }

  # Private DNS zone managed separately; module doesn't accept private_dns_zone_id input.

  default_agent_pool = {
    name           = "systempool"
    vm_size        = "Standard_DS2_v2"
    vnet_subnet_id = module.virtual_network.subnets[local.subnet_names.aks].resource_id
  }
}

module "container_registry" {
  source  = "Azure/avm-res-containerregistry-registry/azurerm"
  version = "0.5.1"

  enable_telemetry   = false
  name               = replace(module.naming.container_registry.name, "-", "")
  location           = var.location
  resource_group_name = module.resource_group.name
  tags               = local.tags
  public_network_access_enabled = false
  diagnostic_settings = local.diagnostic_settings
}

module "app_service_plan" {
  source  = "Azure/avm-res-web-serverfarm/azurerm"
  version = "1.0.0"

  enable_telemetry    = false
  name                = local.app_service_plan_name
  location            = var.location
  resource_group_name = module.resource_group.name
  os_type             = "Windows"
  sku_name            = "P1v3"
  zone_balancing_enabled = false
  tags                = local.tags
}

module "web_app_frontend" {
  source  = "Azure/avm-res-web-site/azurerm"
  version = "0.19.3"

  enable_telemetry          = false
  name                      = local.app_service_names.frontend
  location                  = var.location
  resource_group_name       = module.resource_group.name
  kind                      = "webapp"
  os_type                   = "Windows"
  service_plan_resource_id  = module.app_service_plan.resource_id
  https_only                = true
  virtual_network_subnet_id = module.virtual_network.subnets[local.subnet_names.appsvc_integration].resource_id
  public_network_access_enabled = false
  enable_application_insights   = true
  application_insights = {
    workspace_resource_id = module.log_analytics_workspace.resource_id
  }
  diagnostic_settings           = local.diagnostic_settings
  logs = {
    app_service_logs = {
      application_logs = {
        file_system_level = {
          file_system_level = "Information"
        }
      }
      http_logs = {
        file_system_level = {
          file_system = {
            retention_in_days = 7
            retention_in_mb   = 35
          }
        }
      }
      detailed_error_messages = true
      failed_request_tracing  = true
    }
  }
  managed_identities = {
    system_assigned = true
  }
  site_config = {
    application_stack = {
      default = {
        node_version = "18"
      }
    }
    ip_restriction_default_action     = "Deny"
    scm_ip_restriction_default_action = "Deny"
    ip_restriction                    = local.app_gateway_ip_restrictions
  }
  tags                      = local.tags
}

module "web_app_backend" {
  source  = "Azure/avm-res-web-site/azurerm"
  version = "0.19.3"

  enable_telemetry          = false
  name                      = local.app_service_names.backend
  location                  = var.location
  resource_group_name       = module.resource_group.name
  kind                      = "webapp"
  os_type                   = "Windows"
  service_plan_resource_id  = module.app_service_plan.resource_id
  https_only                = true
  virtual_network_subnet_id = module.virtual_network.subnets[local.subnet_names.appsvc_integration].resource_id
  public_network_access_enabled = false
  enable_application_insights   = true
  application_insights = {
    workspace_resource_id = module.log_analytics_workspace.resource_id
  }
  diagnostic_settings           = local.diagnostic_settings
  logs = {
    app_service_logs = {
      application_logs = {
        file_system_level = {
          file_system_level = "Information"
        }
      }
      http_logs = {
        file_system_level = {
          file_system = {
            retention_in_days = 7
            retention_in_mb   = 35
          }
        }
      }
      detailed_error_messages = true
      failed_request_tracing  = true
    }
  }
  managed_identities = {
    system_assigned = true
  }
  site_config = {
    application_stack = {
      default = {
        dotnet_version = "8.0"
      }
    }
    ip_restriction_default_action     = "Deny"
    scm_ip_restriction_default_action = "Deny"
    ip_restriction                    = local.apim_ip_restrictions
  }
  tags                      = local.tags
}

module "private_endpoints" {
  for_each = local.private_endpoints

  source  = "Azure/avm-res-network-privateendpoint/azurerm"
  version = "0.2.0"

  enable_telemetry       = false
  name                   = each.value.name
  network_interface_name = each.value.network_interface_name
  location               = var.location
  resource_group_name    = module.resource_group.name
  subnet_resource_id     = module.virtual_network.subnets[local.subnet_names.private_endpoints].resource_id
  tags                   = local.tags

  private_connection_resource_id  = each.value.resource_id
  private_service_connection_name = each.value.service_connection_name
  subresource_names               = each.value.subresource_names
  private_dns_zone_group_name     = "default"
  private_dns_zone_resource_ids   = [module.private_dns_zone[each.value.private_dns_zone].resource_id]
}

module "app_gateway_public_ip" {
  source  = "Azure/avm-res-network-publicipaddress/azurerm"
  version = "0.2.1"

  enable_telemetry    = false
  name                = module.naming.public_ip.name
  location            = var.location
  resource_group_name = module.resource_group.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
  diagnostic_settings = local.diagnostic_settings
}

module "application_gateway" {
  source  = "Azure/avm-res-network-applicationgateway/azurerm"
  version = "0.4.3"

  enable_telemetry    = false
  name                = module.naming.application_gateway.name
  location            = var.location
  resource_group_name = module.resource_group.name
  tags                = local.tags
  diagnostic_settings = local.diagnostic_settings

  sku = {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 2
  }

  create_public_ip                 = false
  public_ip_resource_id            = module.app_gateway_public_ip.resource_id
  frontend_ip_configuration_public_name = "appgw-feip-public"

  gateway_ip_configuration = {
    name      = "appgw-ipcfg"
    subnet_id = module.virtual_network.subnets[local.subnet_names.app_gateway].resource_id
  }

  frontend_ports = {
    http = {
      name = "appgw-feport-80"
      port = 80
    }
  }

  backend_address_pools = {
    frontend = {
      name  = "appgw-pool-frontend"
      fqdns = [local.app_service_fqdns.frontend]
    }
    backend = {
      name  = "appgw-pool-backend"
      fqdns = [local.apim_gateway_fqdn]
    }
  }

  probe_configurations = {
    frontend = {
      name                                      = "appgw-probe-frontend"
      protocol                                  = "Https"
      path                                      = "/"
      interval                                  = 30
      timeout                                   = 30
      unhealthy_threshold                       = 3
      pick_host_name_from_backend_http_settings = true
    }
    backend = {
      name                                      = "appgw-probe-backend"
      protocol                                  = "Https"
      path                                      = "/"
      interval                                  = 30
      timeout                                   = 30
      unhealthy_threshold                       = 3
      pick_host_name_from_backend_http_settings = true
    }
  }

  backend_http_settings = {
    frontend = {
      name                                = "appgw-bhs-frontend-https"
      port                                = 443
      protocol                            = "Https"
      request_timeout                     = 60
      pick_host_name_from_backend_address = true
      probe_name                          = "appgw-probe-frontend"
    }
    backend = {
      name                                = "appgw-bhs-backend-https"
      port                                = 443
      protocol                            = "Https"
      request_timeout                     = 60
      pick_host_name_from_backend_address = true
      probe_name                          = "appgw-probe-backend"
    }
  }

  http_listeners = {
    public = {
      name                           = "appgw-listener-public-http"
      frontend_ip_configuration_name = "appgw-feip-public"
      frontend_port_name             = "appgw-feport-80"
      protocol                       = "Http"
    }
  }

  url_path_map_configurations = {
    app = {
      name                               = "appgw-paths-app"
      default_backend_address_pool_name  = "appgw-pool-frontend"
      default_backend_http_settings_name = "appgw-bhs-frontend-https"

      path_rules = {
        api = {
          name                       = "api"
          paths                      = ["/api/*"]
          backend_address_pool_name  = "appgw-pool-backend"
          backend_http_settings_name = "appgw-bhs-backend-https"
        }
      }
    }
  }

  request_routing_rules = {
    public = {
      name               = "appgw-rule-public"
      rule_type          = "PathBasedRouting"
      http_listener_name = "appgw-listener-public-http"
      url_path_map_name  = "appgw-paths-app"
      backend_address_pool_name  = "appgw-pool-frontend"
      backend_http_settings_name = "appgw-bhs-frontend-https"
      priority           = 100
    }
  }

  waf_configuration = {
    enabled          = true
    firewall_mode    = "Prevention"
    rule_set_type    = "OWASP"
    rule_set_version = "3.2"
  }
}

module "api_management" {
  source  = "Azure/avm-res-apimanagement-service/azurerm"
  version = "0.0.6"

  enable_telemetry    = false
  name                = local.apim_name
  location            = var.location
  resource_group_name = module.resource_group.name
  publisher_name      = var.apim_publisher_name
  publisher_email     = var.apim_publisher_email
  sku_name            = var.apim_sku_name
  tags                = local.tags
  diagnostic_settings = local.diagnostic_settings

  virtual_network_type = "Internal"
  virtual_network_subnet_id = module.virtual_network.subnets[local.subnet_names.apim].resource_id
  public_network_access_enabled = true
}

resource "azurerm_api_management_logger" "appinsights" {
  name                = "appinsights"
  resource_group_name = module.resource_group.name
  api_management_name = local.apim_name
  depends_on          = [module.api_management]

  application_insights {
    instrumentation_key = module.application_insights.instrumentation_key
  }
}

resource "azurerm_api_management_diagnostic" "appinsights" {
  identifier                 = "applicationinsights"
  resource_group_name        = module.resource_group.name
  api_management_name        = local.apim_name
  api_management_logger_id   = azurerm_api_management_logger.appinsights.id
  always_log_errors          = true
  sampling_percentage        = 100
  verbosity                  = "information"
  http_correlation_protocol  = "W3C"
}

resource "azurerm_api_management_api" "backend" {
  name                = local.apim_backend_api_name
  resource_group_name = module.resource_group.name
  api_management_name = local.apim_name
  revision            = "1"
  display_name        = "Backend App Service"
  path                = local.apim_backend_api_path
  protocols           = ["https"]
  service_url         = local.apim_backend_url
  subscription_required = false
  depends_on = [module.api_management]
}

module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.10.2"

  enable_telemetry = false
  name             = module.naming.key_vault.name
  location         = var.location
  resource_group_name = module.resource_group.name
  tenant_id        = data.azurerm_client_config.current.tenant_id
  sku_name         = "standard"
  tags             = local.tags
  public_network_access_enabled = false
  diagnostic_settings = local.diagnostic_settings
}

module "servicebus_namespace" {
  source  = "Azure/avm-res-servicebus-namespace/azurerm"
  version = "0.4.0"

  enable_telemetry = false
  name             = module.naming.servicebus_namespace.name
  location         = var.location
  resource_group_name = module.resource_group.name
  sku      = "Premium"
  capacity = 1
  public_network_access_enabled = false
  tags = local.tags
  diagnostic_settings = local.diagnostic_settings
}

module "redis_cache" {
  source  = "Azure/avm-res-cache-redis/azurerm"
  version = "0.4.0"

  enable_telemetry = false
  name             = module.naming.redis_cache.name
  location         = var.location
  resource_group_name = module.resource_group.name
  sku_name         = "Standard"
  capacity         = 1
  zones            = null
  public_network_access_enabled = false
  tags             = local.tags
  diagnostic_settings = local.diagnostic_settings
}

module "storage_account_nsg_logs" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.6.7"

  enable_telemetry = false
  name             = local.storage_account_names.nsg_logs
  location         = var.location
  resource_group_name = module.resource_group.name
  account_kind     = "StorageV2"
  account_tier     = "Standard"
  account_replication_type = "LRS"
  public_network_access_enabled = true
  shared_access_key_enabled      = true
  default_to_oauth_authentication = false
  tags             = local.tags
}

module "storage_account_aks_nfs" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.6.7"

  enable_telemetry = false
  name             = local.storage_account_names.aks_nfs
  location         = var.location
  resource_group_name = module.resource_group.name
  account_kind     = "FileStorage"
  account_tier     = "Premium"
  account_replication_type = "LRS"
  public_network_access_enabled = true
  shared_access_key_enabled      = true
  default_to_oauth_authentication = false
  tags             = local.tags
  diagnostic_settings_storage_account = local.diagnostic_settings_storage_account
  diagnostic_settings_file            = local.diagnostic_settings_file
}

module "storage_account_app_blob" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.6.7"

  enable_telemetry = false
  name             = local.storage_account_names.app_blob
  location         = var.location
  resource_group_name = module.resource_group.name
  account_kind     = "StorageV2"
  account_tier     = "Standard"
  account_replication_type = "LRS"
  public_network_access_enabled = false
  shared_access_key_enabled      = true
  default_to_oauth_authentication = false
  tags             = local.tags
  diagnostic_settings_storage_account = local.diagnostic_settings_storage_account
  diagnostic_settings_blob            = local.diagnostic_settings_blob
}

module "postgresql_flexible_server" {
  source  = "Azure/avm-res-dbforpostgresql-flexibleserver/azurerm"
  version = "0.1.4"

  enable_telemetry = false
  name             = module.naming.postgresql_server.name
  location         = var.location
  resource_group_name = module.resource_group.name
  administrator_login    = local.postgres_admin_login
  administrator_password = random_password.postgres_admin.result
  sku_name         = "B_Standard_B1ms"
  server_version = "15"
  storage_mb       = 32768
  backup_retention_days = 7
  public_network_access_enabled = false
  tags             = local.tags
}

resource "azurerm_postgresql_flexible_server_database" "app" {
  name      = lower(module.naming.postgresql_database.name)
  server_id = module.postgresql_flexible_server.resource_id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

data "azurerm_monitor_diagnostic_categories" "postgresql" {
  resource_id = module.postgresql_flexible_server.resource_id
}

resource "azurerm_monitor_diagnostic_setting" "postgresql" {
  name                       = "diag-postgresql"
  target_resource_id         = module.postgresql_flexible_server.resource_id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  dynamic "enabled_log" {
    for_each = toset(data.azurerm_monitor_diagnostic_categories.postgresql.log_category_types)
    content {
      category = enabled_log.value
    }
  }

  dynamic "metric" {
    for_each = toset(data.azurerm_monitor_diagnostic_categories.postgresql.metric_category_types)
    content {
      category = metric.value
      enabled  = true
    }
  }
}

resource "azurerm_monitor_metric_alert" "postgres_cpu" {
  count               = local.alerts_enabled ? 1 : 0
  name                = "alert-${module.naming.postgresql_server.name}-cpu"
  resource_group_name = module.resource_group.name
  scopes              = [module.postgresql_flexible_server.resource_id]
  description         = "PostgreSQL CPU > 80% for 5 minutes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.alerts[0].id
  }
}

resource "azurerm_monitor_metric_alert" "postgres_memory" {
  count               = local.alerts_enabled ? 1 : 0
  name                = "alert-${module.naming.postgresql_server.name}-memory"
  resource_group_name = module.resource_group.name
  scopes              = [module.postgresql_flexible_server.resource_id]
  description         = "PostgreSQL memory > 80% for 5 minutes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "memory_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.alerts[0].id
  }
}

resource "azurerm_monitor_metric_alert" "postgres_connections" {
  count               = local.alerts_enabled ? 1 : 0
  name                = "alert-${module.naming.postgresql_server.name}-connections"
  resource_group_name = module.resource_group.name
  scopes              = [module.postgresql_flexible_server.resource_id]
  description         = "PostgreSQL active connections > 200 for 5 minutes."
  severity            = 3
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "active_connections"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 200
  }

  action {
    action_group_id = azurerm_monitor_action_group.alerts[0].id
  }
}

module "role_assignments" {
  source  = "Azure/avm-res-authorization-roleassignment/azurerm"
  version = "0.3.0"

  enable_telemetry = false
  role_assignments_azure_resource_manager = local.role_assignments

  depends_on = [
    module.container_registry,
    module.aks,
    module.web_app_frontend,
    module.web_app_backend,
    module.key_vault,
  ]
}
