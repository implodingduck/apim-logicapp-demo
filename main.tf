
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.92.0"
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

data "azurerm_network_security_group" "basic" {
    name                = "basic"
    resource_group_name = "rg-network-eastus"
}

data "azurerm_log_analytics_workspace" "default" {
  name                = "DefaultWorkspace-${data.azurerm_client_config.current.subscription_id}-EUS"
  resource_group_name = "DefaultResourceGroup-EUS"
} 


resource "azurerm_resource_group" "rg" {
  name     = "rg-apim-logicapp-demo-${random_string.unique.result}"
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

# resource "azurerm_subnet_network_security_group_association" "pe" {
#   subnet_id                 = azurerm_subnet.pe.id
#   network_security_group_id = data.azurerm_network_security_group.basic.id
# }

resource "azurerm_subnet" "logicapps" {
  name                  = "snet-logicapps-${local.loc_for_naming}"
  resource_group_name   = azurerm_virtual_network.default.resource_group_name
  virtual_network_name  = azurerm_virtual_network.default.name
  address_prefixes      = ["10.5.0.64/26"]
  service_endpoints = [
    "Microsoft.Web",
    "Microsoft.Storage"
  ]
  delegation {
    name = "serverfarm-delegation"
    service_delegation {
      name = "Microsoft.Web/serverFarms"
    }
  }
}

# resource "azurerm_subnet_network_security_group_association" "logicapps" {
#   subnet_id                 = azurerm_subnet.logicapps.id
#   network_security_group_id = data.azurerm_network_security_group.basic.id
# }

resource "azurerm_subnet" "apim" {
  name                  = "snet-apim-${local.loc_for_naming}"
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

# resource "azurerm_subnet_network_security_group_association" "apim" {
#   subnet_id                 = azurerm_subnet.apim.id
#   network_security_group_id = data.azurerm_network_security_group.basic.id
# }

resource "azurerm_key_vault" "kv" {
  name                       = "apim-logicapp-kv"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled = false

  tags         = local.tags
}

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

resource "azurerm_key_vault_secret" "dbpassword" {
  depends_on = [
    azurerm_key_vault_access_policy.client-config
  ]
  name         = "dbpassword"
  value        = random_password.password.result
  key_vault_id = azurerm_key_vault.kv.id
  tags         = local.tags
}

# module "sql" {
#   source = "github.com/implodingduck/tfmodules//sql"
#   name = local.func_name
#   resource_group_name = azurerm_resource_group.rg.name
#   resource_group_location = azurerm_resource_group.rg.location
#   db_password = random_password.password.result
# }

resource "azurerm_api_management" "apim" {
  name                 = "apim-logicapp-demo-${random_string.unique.result}-api"
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

# data "template_file" "create" {
#   template = file("${path.module}/la-create-entry.json")
#   vars = {
#     subscription_id = data.azurerm_client_config.current.subscription_id
#   }
# }

# resource "azurerm_resource_group_template_deployment" "create" {
#   name = "la-apim-demo-create"
#   resource_group_name = azurerm_resource_group.rg.name
#   deployment_mode = "Incremental"
#   template_content = data.template_file.create.rendered
# }

# data "template_file" "list" {
#   template = file("${path.module}/la-list-entries.json")
#   vars = {
#     subscription_id = data.azurerm_client_config.current.subscription_id
#   }
# }

# resource "azurerm_resource_group_template_deployment" "list" {
#   name = "la-apim-demo-list"
#   resource_group_name = azurerm_resource_group.rg.name
#   deployment_mode = "Incremental"
#   template_content = data.template_file.list.rendered
# }


resource "azurerm_private_dns_zone" "blob" {
  name                      = "privatelink.blob.core.windows.net"
  resource_group_name       = azurerm_resource_group.rg.name
}

# resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
#   name                  = "blob"
#   resource_group_name   = azurerm_resource_group.rg.name
#   private_dns_zone_name = azurerm_private_dns_zone.blob.name
#   virtual_network_id    = azurerm_virtual_network.default.id
# }

resource "azurerm_private_dns_zone" "functions" {
  name                      = "privatelink.azurewebsites.net"
  resource_group_name       = azurerm_resource_group.rg.name
}

# resource "azurerm_private_dns_zone_virtual_network_link" "functions" {
#   name                  = "functions"
#   resource_group_name   = azurerm_resource_group.rg.name
#   private_dns_zone_name = azurerm_private_dns_zone.functions.name
#   virtual_network_id    = azurerm_virtual_network.default.id
# }

# resource "azurerm_private_endpoint" "pe" {
#   name                = "pe-sa${local.func_name}"
#   location            = azurerm_resource_group.rg.location
#   resource_group_name = azurerm_resource_group.rg.name
#   subnet_id           = azurerm_subnet.pe.id

#   private_service_connection {
#     name                           = "pe-connection-sa${local.func_name}"
#     private_connection_resource_id = azurerm_storage_account.sa.id
#     is_manual_connection           = false
#     subresource_names              = ["blob"]
#   }
#   private_dns_zone_group {
#     name                 = azurerm_private_dns_zone.blob.name
#     private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
#   }
# }

# resource "azurerm_private_endpoint" "logicapp" {
#   name                = "pe-la${local.func_name}"
#   location            = azurerm_resource_group.rg.location
#   resource_group_name = azurerm_resource_group.rg.name
#   subnet_id           = azurerm_subnet.pe.id

#   private_service_connection {
#     name                           = "pe-connection-la${local.func_name}"
#     private_connection_resource_id = azurerm_logic_app_standard.example.id
#     is_manual_connection           = false
#     subresource_names              = ["sites"]
#   }
#   private_dns_zone_group {
#     name                 = azurerm_private_dns_zone.functions.name
#     private_dns_zone_ids = [azurerm_private_dns_zone.functions.id]
#   }
# }


resource "azurerm_storage_account" "sa" {
  name                     = "sa${local.func_name}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = local.tags
}

# resource "azurerm_storage_account_network_rules" "fw" {
#   depends_on = [
#     azurerm_app_service_virtual_network_swift_connection.example
#   ]
#   storage_account_id = azurerm_storage_account.sa.id

#   default_action             = "Deny"

#   virtual_network_subnet_ids = [azurerm_subnet.logicapps.id]

#   ip_rules = split(",", azurerm_logic_app_standard.example.possible_outbound_ip_addresses)
# }

resource "azurerm_application_insights" "app" {
  name                = "${local.func_name}-insights"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "other"
  workspace_id = data.azurerm_log_analytics_workspace.default.id
}

resource "azurerm_app_service_plan" "asp" {
  name                = "asp-${local.func_name}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  kind                = "elastic"
  reserved            = false
    sku {
    tier = "WorkflowStandard"
    size = "WS1"
  }
  tags = local.tags
}

resource "azurerm_logic_app_standard" "example" {
  name                       = "la-${local.func_name}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  app_service_plan_id        = azurerm_app_service_plan.asp.id
  storage_account_name       = azurerm_storage_account.sa.name
  storage_account_access_key = azurerm_storage_account.sa.primary_access_key
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"       = "node"
    "WEBSITE_NODE_DEFAULT_VERSION"   = "~12"
    "WEBSITE_CONTENTOVERVNET"        = "1"
    "WEBSITE_VNET_ROUTE_ALL"         = "1"
    "sql_connectionString"           = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.kv.name};SecretName=${azurerm_key_vault_secret.dbconnectionstring.name})"
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.app.instrumentation_key
  }
  identity {
    type = "SystemAssigned"
  }
  tags = local.tags
}

# resource "azurerm_app_service_virtual_network_swift_connection" "example" {
#   app_service_id = azurerm_logic_app_standard.example.id
#   subnet_id      = azurerm_subnet.logicapps.id
# }

resource "azurerm_key_vault_access_policy" "la" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = azurerm_logic_app_standard.example.identity.0.principal_id
  secret_permissions = [
    "get",
    "list"
  ]
}

resource "azurerm_role_assignment" "sa" {
  scope                = azurerm_storage_account.sa.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_logic_app_standard.example.identity.0.principal_id
}
resource "azurerm_key_vault_access_policy" "client-config" {
  key_vault_id = azurerm_key_vault.kv.id
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
    "list",
    "delete"
  ]

  certificate_permissions = [
    "purge"
  ]

  storage_permissions = [
    "purge"
  ]
}


resource "azurerm_key_vault_secret" "dbconnectionstring" {
  depends_on = [
    azurerm_key_vault_access_policy.client-config
  ]
  name         = "dbconnectionstring"
  value        = "helloworld" #"Server=tcp:${module.sql.db_fully_qualified_domain_name},1433;Initial Catalog=${module.sql.db_name};Persist Security Info=False;User ID=sqladmin;Password=${random_password.password.result};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  key_vault_id = azurerm_key_vault.kv.id
}

# resource "azurerm_mssql_firewall_rule" "logicapp" {
#   name             = "logicapp"
#   server_id        = module.sql.db_server_id
#   start_ip_address = "10.5.0.64"
#   end_ip_address   = "10.5.0.127"
# }

