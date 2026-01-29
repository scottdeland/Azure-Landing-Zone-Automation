output "resource_group_name" {
  value = module.resource_group.name
}

output "virtual_network_id" {
  value = module.virtual_network.resource_id
}

output "subnet_ids" {
  value = {
    app_gateway        = module.virtual_network.subnets[local.subnet_names.app_gateway].resource_id
    aks                = module.virtual_network.subnets[local.subnet_names.aks].resource_id
    appsvc_integration = module.virtual_network.subnets[local.subnet_names.appsvc_integration].resource_id
    private_endpoints  = module.virtual_network.subnets[local.subnet_names.private_endpoints].resource_id
    apim               = module.virtual_network.subnets[local.subnet_names.apim].resource_id
  }
}

output "private_dns_zone_ids" {
  value = { for name, zone in module.private_dns_zone : name => zone.resource_id }
}
