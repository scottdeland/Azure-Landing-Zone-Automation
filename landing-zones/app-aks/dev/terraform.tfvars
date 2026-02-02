name_prefix    = "app-aks"
environment    = "dev"
location       = "EastUS2"
location_short = "eus2"
vnet_cidr      = "10.20.0.0/16"

subnet_cidrs = {
  app_gateway        = "10.20.1.0/24"
  aks                = "10.20.12.0/22"
  appsvc_integration = "10.20.6.0/24"
  private_endpoints  = "10.20.7.0/24"
  apim               = "10.20.8.0/24"
}

private_dns_zones = [
  "azure-api.net",
  "privatelink.azure-api.net",
  "privatelink.azurecr.io",
  "privatelink.azurewebsites.net",
  "privatelink.blob.core.windows.net",
  "privatelink.file.core.windows.net",
  "privatelink.postgres.database.azure.com",
  "privatelink.redis.cache.windows.net",
  "privatelink.servicebus.windows.net",
  "privatelink.vaultcore.azure.net",
]

apim_publisher_name  = "Platform Team"
apim_publisher_email = "apim-admin@example.com"
apim_sku_name         = "Developer_1"

tags = {}

alert_email_receivers = [
  "apim-admin@example.com"
]

ghinfra_vnet_name           = "vnet-ghinfra"
ghinfra_resource_group_name = "rg-ghinfra"

avm_versions = {
  resource_group      = "0.4.0"
  virtual_network     = "0.16.0"
  private_dns_zone    = "0.5.0"
  container_registry  = "0.5.0"
  aks                 = "0.3.1"
  api_management      = "0.5.0"
  app_service_plan    = "0.4.0"
  windows_web_app     = "0.6.0"
  private_endpoint    = "0.5.0"
  public_ip           = "0.5.0"
  application_gateway = "0.5.0"
  key_vault           = "0.5.0"
  role_assignment     = "0.3.0"
  servicebus_namespace = "0.5.0"
  redis_cache         = "0.5.0"
  storage_account     = "0.5.0"
  postgresql_flexible_server = "0.5.0"
}
