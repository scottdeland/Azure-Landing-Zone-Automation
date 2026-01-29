locals {
  tags = merge(
    {
      "landing-zone" = var.name_prefix
      "environment"  = var.environment
    },
    var.tags
  )
}

module "naming" {
  source = "../../modules/terraform-azurerm-naming"
  suffix = [var.name_prefix, var.environment, var.location_short]
}

locals {
  subnet_names = {
    app_gateway        = "${module.naming.subnet.name}-appgw"
    aks                = "${module.naming.subnet.name}-aks"
    appsvc_integration = "${module.naming.subnet.name}-appsvc"
    private_endpoints  = "${module.naming.subnet.name}-pep"
    apim               = "${module.naming.subnet.name}-apim"
  }
}

locals {
  apim_nsg_name = "${module.naming.network_security_group.name}-apim"
  app_service_plan_name = module.naming.app_service_plan.name
  app_service_names = {
    frontend = "${module.naming.app_service.name}-fe"
    backend  = "${module.naming.app_service.name}-be"
  }
  app_gateway_subnet_id = module.virtual_network.subnets[local.subnet_names.app_gateway].resource_id
  apim_subnet_id        = module.virtual_network.subnets[local.subnet_names.apim].resource_id
  app_gateway_ip_restrictions = {
    app_gateway = {
      name                      = "allow-appgw"
      priority                  = 100
      action                    = "Allow"
      virtual_network_subnet_id = local.app_gateway_subnet_id
    }
  }
  apim_ip_restrictions = {
    apim = {
      name                      = "allow-apim"
      priority                  = 100
      action                    = "Allow"
      virtual_network_subnet_id = local.apim_subnet_id
    }
  }
  app_service_private_endpoint_names = {
    frontend = "pep-${local.app_service_names.frontend}"
    backend  = "pep-${local.app_service_names.backend}"
  }
  app_service_fqdns = {
    frontend = "${local.app_service_names.frontend}.azurewebsites.net"
    backend  = "${local.app_service_names.backend}.azurewebsites.net"
  }
  apim_name                     = module.naming.api_management.name
  apim_gateway_fqdn             = "${module.naming.api_management.name}.azure-api.net"
  apim_private_endpoint_name    = "pep-${module.naming.api_management.name}"
  apim_private_endpoint_nic_name = "nic-${local.apim_private_endpoint_name}"
  apim_backend_url              = "https://${local.app_service_fqdns.backend}"
  apim_backend_api_name          = "backend"
  apim_backend_api_path          = "api"
}

locals {
  storage_account_base = replace(module.naming.storage_account.name, "-", "")
  storage_account_names = {
    aks_nfs  = substr("${local.storage_account_base}nfs", 0, 24)
    app_blob = substr("${local.storage_account_base}blob", 0, 24)
  }
  sql_admin_login = "sqladminuser"
}

data "azurerm_client_config" "current" {}

resource "random_password" "sql_admin" {
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

resource "azurerm_network_security_group" "apim_gateway" {
  name                = local.apim_nsg_name
  location            = var.location
  resource_group_name = module.resource_group.name
  tags                = local.tags
}

resource "azurerm_network_security_rule" "apim_allow_appgw_https" {
  name                        = "${module.naming.network_security_group_rule.name}-apim-allow-appgw"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["443", "80"]
  source_address_prefix       = var.subnet_cidrs.app_gateway
  destination_address_prefix  = var.subnet_cidrs.apim
  resource_group_name         = module.resource_group.name
  network_security_group_name = azurerm_network_security_group.apim_gateway.name
}

resource "azurerm_network_security_rule" "apim_deny_vnet_http_https" {
  name                        = "${module.naming.network_security_group_rule.name}-apim-deny-vnet"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["443", "80"]
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = var.subnet_cidrs.apim
  resource_group_name         = module.resource_group.name
  network_security_group_name = azurerm_network_security_group.apim_gateway.name
}

resource "azurerm_public_ip" "aks_nat_gateway" {
  name                = "pip-${module.naming.nat_gateway.name}"
  location            = var.location
  resource_group_name = module.resource_group.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "aks" {
  name                = module.naming.nat_gateway.name
  location            = var.location
  resource_group_name = module.resource_group.name
  sku_name            = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "aks" {
  nat_gateway_id       = azurerm_nat_gateway.aks.id
  public_ip_address_id = azurerm_public_ip.aks_nat_gateway.id
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

  subnets = {
    "${local.subnet_names.app_gateway}" = {
      name             = local.subnet_names.app_gateway
      address_prefixes = [var.subnet_cidrs.app_gateway]
    }
    "${local.subnet_names.aks}" = {
      name             = local.subnet_names.aks
      address_prefixes = [var.subnet_cidrs.aks]
      nat_gateway = {
        id = azurerm_nat_gateway.aks.id
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
        id = azurerm_network_security_group.apim_gateway.id
      }
    }
  }
}

module "private_dns_zone" {
  for_each = var.private_dns_zones

  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.4.4"

  enable_telemetry = false
  domain_name      = each.value
  parent_id        = module.resource_group.resource_id
  tags             = local.tags

  virtual_network_links = {
    "vnet-link" = {
      name               = "pdnslink-${replace(each.value, ".", "-")}"
      virtual_network_id = module.virtual_network.resource_id
      registration_enabled = false
    }
  }
}

locals {
  aks_private_dns_zone_name = "privatelink.${lower(replace(var.location, " ", ""))}.azmk8s.io"
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
  managed_identities = {
    system_assigned = true
  }
  site_config = {
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
  managed_identities = {
    system_assigned = true
  }
  site_config = {
    ip_restriction_default_action     = "Deny"
    scm_ip_restriction_default_action = "Deny"
    ip_restriction                    = local.apim_ip_restrictions
  }
  tags                      = local.tags
}

module "web_app_frontend_private_endpoint" {
  source  = "Azure/avm-res-network-privateendpoint/azurerm"
  version = "0.2.0"

  enable_telemetry    = false
  name                = local.app_service_private_endpoint_names.frontend
  network_interface_name = "nic-${local.app_service_private_endpoint_names.frontend}"
  location            = var.location
  resource_group_name = module.resource_group.name
  subnet_resource_id  = module.virtual_network.subnets[local.subnet_names.private_endpoints].resource_id
  tags                = local.tags

  private_connection_resource_id = module.web_app_frontend.resource_id
  private_service_connection_name = "psc-${local.app_service_names.frontend}"
  subresource_names               = ["sites"]
  private_dns_zone_group_name    = "default"
  private_dns_zone_resource_ids   = [module.private_dns_zone["privatelink.azurewebsites.net"].resource_id]
}

module "web_app_backend_private_endpoint" {
  source  = "Azure/avm-res-network-privateendpoint/azurerm"
  version = "0.2.0"

  enable_telemetry    = false
  name                = local.app_service_private_endpoint_names.backend
  network_interface_name = "nic-${local.app_service_private_endpoint_names.backend}"
  location            = var.location
  resource_group_name = module.resource_group.name
  subnet_resource_id  = module.virtual_network.subnets[local.subnet_names.private_endpoints].resource_id
  tags                = local.tags

  private_connection_resource_id = module.web_app_backend.resource_id
  private_service_connection_name = "psc-${local.app_service_names.backend}"
  subresource_names               = ["sites"]
  private_dns_zone_group_name    = "default"
  private_dns_zone_resource_ids   = [module.private_dns_zone["privatelink.azurewebsites.net"].resource_id]
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
}

module "application_gateway" {
  source  = "Azure/avm-res-network-applicationgateway/azurerm"
  version = "0.4.3"

  enable_telemetry    = false
  name                = module.naming.application_gateway.name
  location            = var.location
  resource_group_name = module.resource_group.name
  tags                = local.tags

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

  virtual_network_type = "Internal"
  virtual_network_subnet_id = module.virtual_network.subnets[local.subnet_names.apim].resource_id
  public_network_access_enabled = true
}

module "api_management_private_endpoint" {
  source  = "Azure/avm-res-network-privateendpoint/azurerm"
  version = "0.2.0"

  enable_telemetry       = false
  name                   = local.apim_private_endpoint_name
  network_interface_name = local.apim_private_endpoint_nic_name
  location               = var.location
  resource_group_name    = module.resource_group.name
  subnet_resource_id     = module.virtual_network.subnets[local.subnet_names.private_endpoints].resource_id
  tags                   = local.tags

  private_connection_resource_id  = module.api_management.resource_id
  private_service_connection_name = "psc-${local.apim_name}"
  subresource_names               = ["gateway"]
  private_dns_zone_group_name    = "default"
  private_dns_zone_resource_ids   = [module.private_dns_zone["privatelink.azure-api.net"].resource_id]
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
}

module "sql_server" {
  source  = "Azure/avm-res-sql-server/azurerm"
  version = "0.1.6"

  enable_telemetry = false
  name             = module.naming.mssql_server.name
  location         = var.location
  resource_group_name = module.resource_group.name
  administrator_login          = local.sql_admin_login
  administrator_login_password = random_password.sql_admin.result
  server_version   = "12.0"
  tags             = local.tags
  public_network_access_enabled = false
}

module "sql_database" {
  source  = "Azure/avm-res-sql-server/azurerm//modules/database"
  version = "0.1.6"

  name       = module.naming.mssql_database.name
  sql_server = {
    resource_id = module.sql_server.resource_id
  }
  sku_name = "S0"
  tags     = merge(local.tags, { workload_environment = "development" })
}
locals {
  private_endpoint_names = {
    container_registry = "pep-${module.naming.container_registry.name}"
    key_vault           = "pep-${module.naming.key_vault.name}"
    servicebus          = "pep-${module.naming.servicebus_namespace.name}"
    redis               = "pep-${module.naming.redis_cache.name}"
    storage_aks_nfs      = "pep-${local.storage_account_names.aks_nfs}"
    storage_app_blob     = "pep-${local.storage_account_names.app_blob}"
    sql_database         = "pep-${module.naming.mssql_database.name}"
  }
}

locals {
  role_assignments = {
    aks_acr_pull = {
      principal_id         = module.aks.kubelet_identity.objectId
      role_definition_name = "AcrPull"
      scope                = module.container_registry.resource_id
      principal_type       = "ServicePrincipal"
    }
    web_app_frontend_kv_secrets = {
      principal_id         = module.web_app_frontend.system_assigned_mi_principal_id
      role_definition_name = "Key Vault Secrets User"
      scope                = module.key_vault.resource_id
      principal_type       = "ServicePrincipal"
    }
    web_app_backend_kv_secrets = {
      principal_id         = module.web_app_backend.system_assigned_mi_principal_id
      role_definition_name = "Key Vault Secrets User"
      scope                = module.key_vault.resource_id
      principal_type       = "ServicePrincipal"
    }
  }
}

module "container_registry_private_endpoint" {
  source  = "Azure/avm-res-network-privateendpoint/azurerm"
  version = "0.2.0"

  enable_telemetry       = false
  name                   = local.private_endpoint_names.container_registry
  network_interface_name = "nic-${local.private_endpoint_names.container_registry}"
  location               = var.location
  resource_group_name    = module.resource_group.name
  subnet_resource_id     = module.virtual_network.subnets[local.subnet_names.private_endpoints].resource_id
  tags                   = local.tags

  private_connection_resource_id  = module.container_registry.resource_id
  private_service_connection_name = "psc-${module.naming.container_registry.name}"
  subresource_names               = ["registry"]
  private_dns_zone_group_name    = "default"
  private_dns_zone_resource_ids   = [module.private_dns_zone["privatelink.azurecr.io"].resource_id]
}

module "key_vault_private_endpoint" {
  source  = "Azure/avm-res-network-privateendpoint/azurerm"
  version = "0.2.0"

  enable_telemetry       = false
  name                   = local.private_endpoint_names.key_vault
  network_interface_name = "nic-${local.private_endpoint_names.key_vault}"
  location               = var.location
  resource_group_name    = module.resource_group.name
  subnet_resource_id     = module.virtual_network.subnets[local.subnet_names.private_endpoints].resource_id
  tags                   = local.tags

  private_connection_resource_id  = module.key_vault.resource_id
  private_service_connection_name = "psc-${module.naming.key_vault.name}"
  subresource_names               = ["vault"]
  private_dns_zone_group_name    = "default"
  private_dns_zone_resource_ids   = [module.private_dns_zone["privatelink.vaultcore.azure.net"].resource_id]
}

module "servicebus_private_endpoint" {
  source  = "Azure/avm-res-network-privateendpoint/azurerm"
  version = "0.2.0"

  enable_telemetry       = false
  name                   = local.private_endpoint_names.servicebus
  network_interface_name = "nic-${local.private_endpoint_names.servicebus}"
  location               = var.location
  resource_group_name    = module.resource_group.name
  subnet_resource_id     = module.virtual_network.subnets[local.subnet_names.private_endpoints].resource_id
  tags                   = local.tags

  private_connection_resource_id  = module.servicebus_namespace.resource_id
  private_service_connection_name = "psc-${module.naming.servicebus_namespace.name}"
  subresource_names               = ["namespace"]
  private_dns_zone_group_name    = "default"
  private_dns_zone_resource_ids   = [module.private_dns_zone["privatelink.servicebus.windows.net"].resource_id]
}

module "redis_private_endpoint" {
  source  = "Azure/avm-res-network-privateendpoint/azurerm"
  version = "0.2.0"

  enable_telemetry       = false
  name                   = local.private_endpoint_names.redis
  network_interface_name = "nic-${local.private_endpoint_names.redis}"
  location               = var.location
  resource_group_name    = module.resource_group.name
  subnet_resource_id     = module.virtual_network.subnets[local.subnet_names.private_endpoints].resource_id
  tags                   = local.tags

  private_connection_resource_id  = module.redis_cache.resource_id
  private_service_connection_name = "psc-${module.naming.redis_cache.name}"
  subresource_names               = ["redisCache"]
  private_dns_zone_group_name    = "default"
  private_dns_zone_resource_ids   = [module.private_dns_zone["privatelink.redis.cache.windows.net"].resource_id]
}

module "storage_account_aks_nfs_private_endpoint" {
  source  = "Azure/avm-res-network-privateendpoint/azurerm"
  version = "0.2.0"

  enable_telemetry       = false
  name                   = local.private_endpoint_names.storage_aks_nfs
  network_interface_name = "nic-${local.private_endpoint_names.storage_aks_nfs}"
  location               = var.location
  resource_group_name    = module.resource_group.name
  subnet_resource_id     = module.virtual_network.subnets[local.subnet_names.private_endpoints].resource_id
  tags                   = local.tags

  private_connection_resource_id  = module.storage_account_aks_nfs.resource_id
  private_service_connection_name = "psc-${local.storage_account_names.aks_nfs}"
  subresource_names               = ["file"]
  private_dns_zone_group_name    = "default"
  private_dns_zone_resource_ids   = [module.private_dns_zone["privatelink.file.core.windows.net"].resource_id]
}

module "storage_account_app_blob_private_endpoint" {
  source  = "Azure/avm-res-network-privateendpoint/azurerm"
  version = "0.2.0"

  enable_telemetry       = false
  name                   = local.private_endpoint_names.storage_app_blob
  network_interface_name = "nic-${local.private_endpoint_names.storage_app_blob}"
  location               = var.location
  resource_group_name    = module.resource_group.name
  subnet_resource_id     = module.virtual_network.subnets[local.subnet_names.private_endpoints].resource_id
  tags                   = local.tags

  private_connection_resource_id  = module.storage_account_app_blob.resource_id
  private_service_connection_name = "psc-${local.storage_account_names.app_blob}"
  subresource_names               = ["blob"]
  private_dns_zone_group_name    = "default"
  private_dns_zone_resource_ids   = [module.private_dns_zone["privatelink.blob.core.windows.net"].resource_id]
}

module "sql_database_private_endpoint" {
  source  = "Azure/avm-res-network-privateendpoint/azurerm"
  version = "0.2.0"

  enable_telemetry       = false
  name                   = local.private_endpoint_names.sql_database
  network_interface_name = "nic-${local.private_endpoint_names.sql_database}"
  location               = var.location
  resource_group_name    = module.resource_group.name
  subnet_resource_id     = module.virtual_network.subnets[local.subnet_names.private_endpoints].resource_id
  tags                   = local.tags

  private_connection_resource_id  = module.sql_database.resource_id
  private_service_connection_name = "psc-${module.naming.mssql_database.name}"
  subresource_names               = ["sqlDatabase"]
  private_dns_zone_group_name    = "default"
  private_dns_zone_resource_ids   = [module.private_dns_zone["privatelink.database.windows.net"].resource_id]
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
