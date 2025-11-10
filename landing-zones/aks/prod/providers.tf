terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=3.66.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "2.3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.7.1"
    }
  }
  backend "azurerm" {
    subscription_id      = "TBD"
    resource_group_name  = "rg-github-actions-runner"
    storage_account_name = "saprodghrunner"
    container_name       = "solutions"
    key                  = "solution-aks-lz-prod.tfstate"
  }
}

provider "azurerm" {
  features {}
  subscription_id = "TBD"
}