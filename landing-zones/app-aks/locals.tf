locals {
  # Common tags applied to all resources.
  tags = merge(
    {
      "landing-zone" = var.name_prefix
      "environment"  = var.environment
    },
    var.tags
  )

  # Standardized subnet names used across modules.
  subnet_names = {
    app_gateway        = "${module.naming.subnet.name}-appgw"
    aks                = "${module.naming.subnet.name}-aks"
    appsvc_integration = "${module.naming.subnet.name}-appsvc"
    private_endpoints  = "${module.naming.subnet.name}-pep"
    apim               = "${module.naming.subnet.name}-apim"
  }

  # APIM NSG name derived from naming module.
  apim_nsg_name = "${module.naming.network_security_group.name}-apim"
  # App Service Plan name used for web apps.
  app_service_plan_name = module.naming.app_service_plan.name
  # Frontend/back-end web app names.
  app_service_names = {
    frontend = "${module.naming.app_service.name}-fe"
    backend  = "${module.naming.app_service.name}-be"
  }

  # Subnet IDs for gateway and APIM used in IP restrictions.
  app_gateway_subnet_id = module.virtual_network.subnets[local.subnet_names.app_gateway].resource_id
  apim_subnet_id        = module.virtual_network.subnets[local.subnet_names.apim].resource_id
  # App Gateway IP restrictions for the frontend app.
  app_gateway_ip_restrictions = {
    app_gateway = {
      name                      = "allow-appgw"
      priority                  = 100
      action                    = "Allow"
      ip_address                = var.subnet_cidrs.app_gateway
    }
  }

  # APIM IP restrictions for the backend app.
  apim_ip_restrictions = {
    apim = {
      name                      = "allow-apim"
      priority                  = 100
      action                    = "Allow"
      ip_address                = var.subnet_cidrs.apim
    }
  }


  # Default App Service FQDNs for APIM/backend integration.
  app_service_fqdns = {
    frontend = "${local.app_service_names.frontend}.azurewebsites.net"
    backend  = "${local.app_service_names.backend}.azurewebsites.net"
  }

  # APIM resource names and URLs.
  apim_name                     = module.naming.api_management.name
  apim_gateway_fqdn             = "${module.naming.api_management.name}.azure-api.net"
  # apim_private_ip               = module.api_management.private_ip_addresses[0]
  apim_private_endpoint_name    = "pep-${module.naming.api_management.name}"
  apim_private_endpoint_nic_name = "nic-${local.apim_private_endpoint_name}"
  apim_backend_url              = "https://${local.app_service_fqdns.backend}"
  apim_backend_api_name          = "backend"
  apim_backend_api_path          = "api"

  # Base storage account name (stripped) for derived names.
  storage_account_base = replace(module.naming.storage_account.name, "-", "")
  # Storage account names for NFS and blob.
  storage_account_names = {
    aks_nfs  = substr("${local.storage_account_base}nfs", 0, 24)
    app_blob = substr("${local.storage_account_base}blob", 0, 24)
    nsg_logs = substr("${local.storage_account_base}nsg", 0, 24)
  }
  # PostgreSQL admin login name.
  # postgres_admin_login = "pgadminuser"

  # AKS private DNS zone name for the selected region.
  aks_private_dns_zone_name = "privatelink.${lower(replace(var.location, " ", ""))}.azmk8s.io"

  # Private DNS zones map for module iteration.
  private_dns_zones = { for zone in var.private_dns_zones : zone => zone }

  # Private endpoint definitions for looped deployment.
  private_endpoints = {
    web_app_frontend = {
      name                   = "pep-${local.app_service_names.frontend}"
      network_interface_name = "nic-pep-${local.app_service_names.frontend}"
      resource_id          = module.web_app_frontend.resource_id
      service_connection_name = "psc-${local.app_service_names.frontend}"
      subresource_names    = ["sites"]
      private_dns_zone     = "privatelink.azurewebsites.net"
    }
    web_app_backend = {
      name                   = "pep-${local.app_service_names.backend}"
      network_interface_name = "nic-pep-${local.app_service_names.backend}"
      resource_id          = module.web_app_backend.resource_id
      service_connection_name = "psc-${local.app_service_names.backend}"
      subresource_names    = ["sites"]
      private_dns_zone     = "privatelink.azurewebsites.net"
    }
#    api_management = {
#      name                   = local.apim_private_endpoint_name
#      network_interface_name = local.apim_private_endpoint_nic_name
#      resource_id            = module.api_management.resource_id
#      service_connection_name = "psc-${local.apim_name}"
#      subresource_names      = ["gateway"]
#      private_dns_zone       = "privatelink.azure-api.net"
#    }
    container_registry = {
      name                   = "pep-${module.naming.container_registry.name}"
      network_interface_name = "nic-pep-${module.naming.container_registry.name}"
      resource_id          = module.container_registry.resource_id
      service_connection_name = "psc-${module.naming.container_registry.name}"
      subresource_names    = ["registry"]
      private_dns_zone     = "privatelink.azurecr.io"
    }
    key_vault = {
      name                   = "pep-${module.naming.key_vault.name}"
      network_interface_name = "nic-pep-${module.naming.key_vault.name}"
      resource_id          = module.key_vault.resource_id
      service_connection_name = "psc-${module.naming.key_vault.name}"
      subresource_names    = ["vault"]
      private_dns_zone     = "privatelink.vaultcore.azure.net"
    }
    servicebus = {
      name                   = "pep-${module.naming.servicebus_namespace.name}"
      network_interface_name = "nic-pep-${module.naming.servicebus_namespace.name}"
      resource_id          = module.servicebus_namespace.resource_id
      service_connection_name = "psc-${module.naming.servicebus_namespace.name}"
      subresource_names    = ["namespace"]
      private_dns_zone     = "privatelink.servicebus.windows.net"
    }
    redis = {
      name                   = "pep-${module.naming.redis_cache.name}"
      network_interface_name = "nic-pep-${module.naming.redis_cache.name}"
      resource_id          = module.redis_cache.resource_id
      service_connection_name = "psc-${module.naming.redis_cache.name}"
      subresource_names    = ["redisCache"]
      private_dns_zone     = "privatelink.redis.cache.windows.net"
    }
    storage_aks_nfs = {
      name                   = "pep-${local.storage_account_names.aks_nfs}"
      network_interface_name = "nic-pep-${local.storage_account_names.aks_nfs}"
      resource_id          = module.storage_account_aks_nfs.resource_id
      service_connection_name = "psc-${local.storage_account_names.aks_nfs}"
      subresource_names    = ["file"]
      private_dns_zone     = "privatelink.file.core.windows.net"
    }
    storage_app_blob = {
      name                   = "pep-${local.storage_account_names.app_blob}"
      network_interface_name = "nic-pep-${local.storage_account_names.app_blob}"
      resource_id          = module.storage_account_app_blob.resource_id
      service_connection_name = "psc-${local.storage_account_names.app_blob}"
      subresource_names    = ["blob"]
      private_dns_zone     = "privatelink.blob.core.windows.net"
    }
    # postgresql_server = {
    #   name                   = "pep-${module.naming.postgresql_server.name}"
    #   network_interface_name = "nic-pep-${module.naming.postgresql_server.name}"
    #   resource_id          = module.postgresql_flexible_server.resource_id
    #   service_connection_name = "psc-${module.naming.postgresql_server.name}"
    #   subresource_names    = ["postgresqlServer"]
    #   private_dns_zone     = "privatelink.postgres.database.azure.com"
    # }
  }

  # Role assignment definitions (name, scope, role) for consistent iteration.
  role_assignment_definitions = {
    aks_acr_pull = {
      name                 = "aks-acr-pull"
      principal_id         = module.aks.kubelet_identity.objectId
      role_definition_name = "AcrPull"
      scope                = module.container_registry.resource_id
      principal_type       = "ServicePrincipal"
    }
    aks_kv_secrets = {
      name                 = "aks-kv-secrets"
      principal_id         = module.aks.kubelet_identity.objectId
      role_definition_name = "Key Vault Secrets User"
      scope                = module.key_vault.resource_id
      principal_type       = "ServicePrincipal"
    }
    web_app_frontend_kv_secrets = {
      name                 = "web-frontend-kv-secrets"
      principal_id         = module.web_app_frontend.system_assigned_mi_principal_id
      role_definition_name = "Key Vault Secrets User"
      scope                = module.key_vault.resource_id
      principal_type       = "ServicePrincipal"
    }
    web_app_frontend_blob = {
      name                 = "web-frontend-blob"
      principal_id         = module.web_app_frontend.system_assigned_mi_principal_id
      role_definition_name = "Storage Blob Data Contributor"
      scope                = module.storage_account_app_blob.resource_id
      principal_type       = "ServicePrincipal"
    }
    web_app_backend_kv_secrets = {
      name                 = "web-backend-kv-secrets"
      principal_id         = module.web_app_backend.system_assigned_mi_principal_id
      role_definition_name = "Key Vault Secrets User"
      scope                = module.key_vault.resource_id
      principal_type       = "ServicePrincipal"
    }
    aks_storage_nfs = {
      name                 = "aks-storage-nfs"
      principal_id         = module.aks.kubelet_identity.objectId
      role_definition_name = "Storage File Data Privileged Contributor"
      scope                = module.storage_account_aks_nfs.resource_id
      principal_type       = "ServicePrincipal"
    }
  }

  # Role assignments shaped for the AVM role assignment module input.
  role_assignments = {
    for key, assignment in local.role_assignment_definitions : key => {
      principal_id         = assignment.principal_id
      role_definition_name = assignment.role_definition_name
      scope                = assignment.scope
      principal_type       = assignment.principal_type
    }
  }

  # Default diagnostic settings that send logs/metrics to Log Analytics.
  diagnostic_settings = {
    default = {
      name                          = "diag"
      log_analytics_destination_type = "Dedicated"
      workspace_resource_id         = module.log_analytics_workspace.resource_id
      log_groups                    = ["allLogs"]
      metric_categories             = ["AllMetrics"]
    }
  }


  # AKS diagnostic settings (includes audit logs via allLogs group).
  aks_diagnostic_settings = {
    default = {
      name                          = "diag-aks"
      log_analytics_destination_type = "Dedicated"
      workspace_resource_id         = module.log_analytics_workspace.resource_id
      log_groups                    = ["allLogs"]
      metric_categories             = ["AllMetrics"]
    }
  }

  # Enable alerting resources only when receivers are configured.
  alerts_enabled = length(var.alert_email_receivers) > 0

  # Storage account diagnostic settings for account-level metrics.
  diagnostic_settings_storage_account = {
    default = {
      name                          = "diag"
      log_analytics_destination_type = "Dedicated"
      workspace_resource_id         = module.log_analytics_workspace.resource_id
      metric_categories             = ["Transaction"]
    }
  }

  # Storage blob diagnostics for read/write/delete events and metrics.
  diagnostic_settings_blob = {
    default = {
      name                          = "diag"
      log_analytics_destination_type = "Dedicated"
      workspace_resource_id         = module.log_analytics_workspace.resource_id
      log_categories                = ["StorageRead", "StorageWrite", "StorageDelete"]
      metric_categories             = ["Transaction"]
      log_groups                    = []
    }
  }

  # Storage file diagnostics for read/write/delete events and metrics.
  diagnostic_settings_file = {
    default = {
      name                          = "diag"
      log_analytics_destination_type = "Dedicated"
      workspace_resource_id         = module.log_analytics_workspace.resource_id
      log_categories                = ["StorageRead", "StorageWrite", "StorageDelete"]
      metric_categories             = ["Transaction"]
      log_groups                    = []
    }
  }
}
