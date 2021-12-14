
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
  tags         = {}
}

module "sql" {
  source = "github.com/implodingduck/tfmodules//sql"
  name = local.func_name
  resource_group_name = azurerm_resource_group.rg.name
  resource_group_location = azurerm_resource_group.rg.location
  db_password = random_password.password.result
}

resource "azurerm_api_management" "apim" {
  name                = "apim-logicapp-demo-tf-api"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  publisher_name      = "implodingduck"
  publisher_email     = "something@nothing.com"

  sku_name = "Developer_1"
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

data "template_file" "create" {
  template = file("${path.module}/la-create-entry.json")
  vars = {
    subscription_id = data.azurerm_client_config.subscription_id
  }
}

resource "azurerm_resource_group_template_deployment" "create" {
  name = "la-apim-demo-create"
  resource_group_name = azurerm_resource_group.rg.name
  deployment_mode = "Incremental"
  template_content = data.template_file.create.rendered
}