variable "name_prefix" {
  type        = string
  description = "Prefix used for resource naming."
  default     = "app-aks"
}

variable "environment" {
  type        = string
  description = "Deployment environment name (e.g., dev, prod)."
  default     = "dev"
}

variable "location" {
  type        = string
  description = "Azure region for resources."
  default     = "EastUS2"
}

variable "location_short" {
  type        = string
  description = "Short Azure region code used in names."
  default     = "eus2"
}

variable "vnet_cidr" {
  type        = string
  description = "CIDR block for the landing zone VNet."
  default     = "10.20.0.0/16"
}

variable "subnet_cidrs" {
  type        = map(string)
  description = "Subnet CIDR blocks for the landing zone."
  default = {
    app_gateway        = "10.20.1.0/24"
    aks                = "10.20.2.0/22"
    appsvc_integration = "10.20.6.0/24"
    private_endpoints  = "10.20.7.0/24"
    apim               = "10.20.8.0/24"
  }
}

variable "private_dns_zones" {
  type        = set(string)
  description = "Private DNS zones required for private endpoints."
  default = [
    "privatelink.azure-api.net",
    "privatelink.azurecr.io",
    "privatelink.azurewebsites.net",
    "privatelink.blob.core.windows.net",
    "privatelink.database.windows.net",
    "privatelink.file.core.windows.net",
    "privatelink.redis.cache.windows.net",
    "privatelink.servicebus.windows.net",
    "privatelink.vaultcore.azure.net",
  ]
}

variable "apim_publisher_name" {
  type        = string
  description = "Publisher name for API Management."
  default     = "Platform Team"
}

variable "apim_publisher_email" {
  type        = string
  description = "Publisher email for API Management."
  default     = "apim-admin@example.com"
}

variable "apim_sku_name" {
  type        = string
  description = "SKU name for API Management."
  default     = "Developer_1"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources."
  default     = {}
}

variable "alert_email_receivers" {
  type        = list(string)
  description = "Email addresses to receive Azure Monitor alerts."
  default     = []
}

variable "ghinfra_vnet_name" {
  type        = string
  description = "Name of the GitHub runner VNet for peering."
  default     = "vnet-ghinfra"
}

variable "ghinfra_resource_group_name" {
  type        = string
  description = "Resource group name of the GitHub runner VNet."
  default     = "rg-ghinfra"
}

variable "avm_versions" {
  type = object({
    resource_group      = string
    virtual_network     = string
    private_dns_zone    = string
    container_registry  = string
    aks                 = string
    api_management      = string
    app_service_plan    = string
    windows_web_app     = string
    private_endpoint    = string
    public_ip           = string
    application_gateway = string
    key_vault           = string
    role_assignment     = string
    servicebus_namespace = string
    redis_cache         = string
    storage_account     = string
    sql_server          = string
    sql_database        = string
  })
  description = "Pinned versions for Azure Verified Modules used by this landing zone."
  default = {
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
    sql_server          = "0.5.0"
    sql_database        = "0.5.0"
  }
}
