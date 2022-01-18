
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.62.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "=3.1.0"
    }
  }
  backend "azurerm" {

  }
}

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
}

locals {
  func_name = "sctf${random_string.unique.result}"
  loc_for_naming = lower(replace(var.location, " ", ""))
  tags = {
    "managed_by" = "terraform"
    "repo"       = "apim-logicapp-demo"
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = "rg-apim-logicapp-demo-tf"
  location = var.location
}

resource "random_string" "unique" {
  length  = 8
  special = false
  upper   = false
}

resource "azurerm_virtual_network" "default" {
  name                = "vnet-${local.func_name}-${local.loc_for_naming}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.5.0.0/24"]

  tags = local.tags
}

resource "azurerm_subnet" "pe" {
  name                  = "snet-privateendpoints-${local.loc_for_naming}"
  resource_group_name   = azurerm_virtual_network.default.resource_group_name
  virtual_network_name  = azurerm_virtual_network.default.name
  address_prefixes      = ["10.5.0.0/26"]

  enforce_private_link_endpoint_network_policies = true

}

resource "azurerm_subnet" "logicapps" {
  name                  = "snet-logicapps-${local.loc_for_naming}"
  resource_group_name   = azurerm_virtual_network.default.resource_group_name
  virtual_network_name  = azurerm_virtual_network.default.name
  address_prefixes      = ["10.5.0.64/26"]
  delegation {
    name = "serverfarm-delegation"
    service_delegation {
      name = "Microsoft.Web/serverFarms"
    }
  }
  

 
}

resource "azurerm_subnet" "apim" {
  name                  = "snet-logicapps-${local.loc_for_naming}"
  resource_group_name   = azurerm_virtual_network.default.resource_group_name
  virtual_network_name  = azurerm_virtual_network.default.name
  address_prefixes      = ["10.5.0.128/26"]
  delegation {
    name = "apimanagement-delegation"
    service_delegation {
      name = "Microsoft.ApiManagement/service"
    }
  }
  

 
}

resource "azurerm_key_vault" "kv" {
  name                       = "apim-logicapp-kv"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled = false

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "create",
      "get",
      "purge",
      "recover",
      "delete"
    ]

    secret_permissions = [
      "set",
      "purge",
      "get",
      "list"
    ]

    certificate_permissions = [
      "purge"
    ]

    storage_permissions = [
      "purge"
    ]
  }
  tags         = local.tags
}

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

resource "azurerm_key_vault_secret" "dbpassword" {
  name         = "dbpassword"
  value        = random_password.password.result
  key_vault_id = azurerm_key_vault.kv.id
  tags         = local.tags
}

module "sql" {
  source = "github.com/implodingduck/tfmodules//sql"
  name = local.func_name
  resource_group_name = azurerm_resource_group.rg.name
  resource_group_location = azurerm_resource_group.rg.location
  db_password = random_password.password.result
}

resource "azurerm_api_management" "apim" {
  name                 = "apim-logicapp-demo-tf-api"
  location             = azurerm_resource_group.rg.location
  resource_group_name  = azurerm_resource_group.rg.name
  publisher_name       = "implodingduck"
  publisher_email      = "something@nothing.com"
  virtual_network_type = "Internal"
  virtual_network_configuration {
    subnet_id = azurerm_subnet.apim.id
  }

  sku_name = "Developer_1"
  tags = local.tags
}

resource "azurerm_api_management_api" "api" {
  name                = "logic-app-api"
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  revision            = "1"
  display_name        = "LogicApp API"
  path                = "logicapp"
  protocols           = ["https"]

}

resource "azurerm_api_management_api_operation" "create" {
  operation_id        = "terms-create"
  api_name            = azurerm_api_management_api.api.name
  api_management_name = azurerm_api_management_api.api.api_management_name
  resource_group_name = azurerm_api_management_api.api.resource_group_name
  display_name        = "Create a term"
  method              = "POST"
  url_template        = "/terms"
  description         = "create description"

  request {
    representation {
      content_type = "application/json"
    }
  }
  response {
    status_code = 200
    representation {
      content_type = "application/json"
    }
  }
}



resource "azurerm_api_management_api_operation" "list" {
  operation_id        = "terms-list"
  api_name            = azurerm_api_management_api.api.name
  api_management_name = azurerm_api_management_api.api.api_management_name
  resource_group_name = azurerm_api_management_api.api.resource_group_name
  display_name        = "list all terms"
  method              = "GET"
  url_template        = "/terms"
  description         = "list description"
  
  request {
    representation {
      content_type = "application/json"
    }
  }
  response {
    status_code = 200
    representation {
      content_type = "application/json"
    }
  }
}

data "template_file" "create" {
  template = file("${path.module}/la-create-entry.json")
  vars = {
    subscription_id = data.azurerm_client_config.current.subscription_id
  }
}

resource "azurerm_resource_group_template_deployment" "create" {
  name = "la-apim-demo-create"
  resource_group_name = azurerm_resource_group.rg.name
  deployment_mode = "Incremental"
  template_content = data.template_file.create.rendered
}

data "template_file" "list" {
  template = file("${path.module}/la-list-entries.json")
  vars = {
    subscription_id = data.azurerm_client_config.current.subscription_id
  }
}

resource "azurerm_resource_group_template_deployment" "list" {
  name = "la-apim-demo-list"
  resource_group_name = azurerm_resource_group.rg.name
  deployment_mode = "Incremental"
  template_content = data.template_file.list.rendered
}