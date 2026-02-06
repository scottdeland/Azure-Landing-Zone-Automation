terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=3.66.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.7.0, < 3.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.7.1"
    }
  }
      backend "azurerm" {
    environment          = "public"
    resource_group_name  = "rg-gh-services"
    storage_account_name = "satfstatedeland"
    container_name       = "tfstate"
    key                  = "appaks.tfstate"
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = "ab66f873-5466-4456-a693-780c6c173733"
}
