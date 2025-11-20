variable "owner" {
  type        = string
  description = "Github Repository Owner"
}

variable "repo" {
  type        = string
  description = "Github Repository Name"
}

variable "github_pat" {
  type        = string
  description = "Github Personal Access Token"
}

variable "runner_name" {
  type        = string
  description = "Name of the Github runner"
}

variable "location" {
  type        = string
  description = "Location of the Azure resources"
}

variable "subnet_name" {
  type        = string
  description = "Name of the existing subnet to deploy the runner. If null/empty, a new subnet will be created."
  default     = null
}

variable "vnet_resource_group_name" {
  type        = string
  description = "Resource group name of the existing Virtual Network. If null/empty and no existing VNet is specified, a new VNet will be created in the module's resource group."
  default     = null
}

variable "virtual_network_name" {
  type        = string
  description = "Name of the existing virtual network. If null/empty, a new VNet will be created."
  default     = null
}

variable "container_image" {
  type        = string
  description = "Container image to use for the runner"
}

variable "azure_environment" {
  type        = string
  description = "Azure Environment"
  default     = "public"
}

variable "vnet_address_space" {
  type        = list(string)
  description = "Address space for the VNet if created. Ignored when using an existing VNet."
  default     = ["10.200.0.0/16"]
}

variable "subnet_address_prefixes" {
  type        = list(string)
  description = "Address prefixes for the subnet if created. Ignored when using an existing subnet."
  default     = ["10.200.1.0/24"]
}
