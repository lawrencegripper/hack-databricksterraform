variable group_name {}

provider "azurerm" {
  version = "~> 2.3"
  features {}
}

provider "azuread" {
  version = "~> 0.8"
}

provider "random" {
  version = "~> 2.2"
}

resource "random_string" "name_prefix" {
  special = false
  upper   = false
  length  = 6
}

resource "azurerm_resource_group" "example" {
  name     = var.group_name
  location = "eastus" # note must be lower without spaces not verbose style
}

resource "azurerm_databricks_workspace" "example" {
  name                = "databricks-test"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  sku                 = "standard"
}

# Configure Datalake and SP for access
resource "azurerm_storage_account" "account" {
  name                     = "${random_string.name_prefix.result}datalake"
  resource_group_name      = azurerm_resource_group.example.name
  location                 = azurerm_resource_group.example.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = "true"
}

resource "azuread_application" "datalake" {
  name                       = "${random_string.name_prefix.result}datalake"
  identifier_uris            = ["http://${random_string.name_prefix.result}datalake"]
  available_to_other_tenants = false
  oauth2_allow_implicit_flow = true

}

resource "azuread_service_principal" "datalake" {
  application_id               = azuread_application.datalake.application_id
  app_role_assignment_required = false
}

resource "random_string" "pw" {
  length = 24
}

resource "azuread_service_principal_password" "datalake" {
  service_principal_id = azuread_service_principal.datalake.id
  value                = random_string.pw.result
  # Review best way forward with this setting
  end_date = "2050-01-01T01:02:03Z"
}

resource "azurerm_role_assignment" "datalake" {
  scope = azurerm_storage_account.account.id
  #https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#storage-blob-data-contributor
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.datalake.id
}

# Create cluster
resource "shell_script" "pat_token" {
  lifecycle_commands {
    create = "pwsh ${path.module}/scripts/pat.ps1 -type create"
    read   = "pwsh ${path.module}/scripts/pat.ps1 -type read"
    update = "pwsh ${path.module}/scripts/pat.ps1 -type update"
    delete = "pwsh ${path.module}/scripts/pat.ps1 -type delete"
  }

  working_directory = path.module

  environment = {
    pat_token_name  = "tf_pat_token"
    workspace_id    = azurerm_databricks_workspace.example.id
    DATABRICKS_HOST = "https://${azurerm_resource_group.example.location}.azuredatabricks.net"
  }
}

resource "shell_script" "cluster" {
  lifecycle_commands {
    create = "pwsh ${path.module}/scripts/cluster.ps1 -type create"
    read   = "pwsh ${path.module}/scripts/cluster.ps1 -type read"
    update = "pwsh ${path.module}/scripts/cluster.ps1 -type update"
    delete = "pwsh ${path.module}/scripts/cluster.ps1 -type delete"
  }

  working_directory = path.module

  environment = {
    DATABRICKS_HOST  = "https://${azurerm_resource_group.example.location}.azuredatabricks.net"
    DATABRICKS_TOKEN = shell_script.pat_token.output["token_value"]
    wait_for_state   = "PENDING"
    debug_log        = true
    # Enabled passthrough for single user.
    # `jsonencode(jsondecode(x))` ensures invalid json fails during plan stage
    # not midway through a deployment -> fail fast and early if you miss a comma. 
    cluster_json = jsonencode(jsondecode(<<JSON
      {
        "cluster_name": "my-cluster-t1",
        "spark_version": "6.4.x-scala2.11",
        "node_type_id": "Standard_D3_v2",
        "num_workers": "1",
        "autotermination_minutes": 300
    }
JSON
    ))
  }
}


resource "shell_script" "secret_scope" {
  lifecycle_commands {
    create = "pwsh ${path.module}/scripts/secretscope.ps1 -type create"
    read   = "pwsh ${path.module}/scripts/secretscope.ps1 -type read"
    update = "pwsh ${path.module}/scripts/secretscope.ps1 -type update"
    delete = "pwsh ${path.module}/scripts/secretscope.ps1 -type delete"
  }

  environment = {
    DATABRICKS_HOST          = "https://${azurerm_resource_group.example.location}.azuredatabricks.net"
    DATABRICKS_TOKEN         = shell_script.pat_token.output["token_value"]
    secret_scope_name        = "terraform"
    initial_manage_principal = "users"
    debug_log                = true
  }
}

resource "shell_script" "secret_sp_applicationid" {
  lifecycle_commands {
    create = "pwsh ${path.module}/scripts/secret.ps1 -type create"
    read   = "pwsh ${path.module}/scripts/secret.ps1 -type read"
    update = "pwsh ${path.module}/scripts/secret.ps1 -type update"
    delete = "pwsh ${path.module}/scripts/secret.ps1 -type delete"
  }

  environment = {
    DATABRICKS_HOST   = "https://${azurerm_resource_group.example.location}.azuredatabricks.net"
    DATABRICKS_TOKEN  = shell_script.pat_token.output["token_value"]
    secret_scope_name = shell_script.secret_scope.output["name"]
    secret_name       = "datalake_sp_applicationid"
    secret_value      = azuread_application.datalake.application_id
    debug_log         = true
  }
}


resource "shell_script" "secret_app_client_secret" {
  lifecycle_commands {
    create = "pwsh ${path.module}/scripts/secret.ps1 -type create"
    read   = "pwsh ${path.module}/scripts/secret.ps1 -type read"
    update = "pwsh ${path.module}/scripts/secret.ps1 -type update"
    delete = "pwsh ${path.module}/scripts/secret.ps1 -type delete"
  }

  environment = {
    DATABRICKS_HOST   = "https://${azurerm_resource_group.example.location}.azuredatabricks.net"
    DATABRICKS_TOKEN  = shell_script.pat_token.output["token_value"]
    secret_scope_name = shell_script.secret_scope.output["name"]
    secret_name       = "datalake_sp_client_secret"
    secret_value      = random_string.pw.result
    debug_log         = true
  }

  depends_on = [
    azuread_service_principal_password.datalake
  ]
}

# Used to get current tenant ID
data "azuread_client_config" "current" {
}

resource "shell_script" "secret_app_tenant" {
  lifecycle_commands {
    create = "pwsh ${path.module}/scripts/secret.ps1 -type create"
    read   = "pwsh ${path.module}/scripts/secret.ps1 -type read"
    update = "pwsh ${path.module}/scripts/secret.ps1 -type update"
    delete = "pwsh ${path.module}/scripts/secret.ps1 -type delete"
  }

  environment = {
    DATABRICKS_HOST   = "https://${azurerm_resource_group.example.location}.azuredatabricks.net"
    DATABRICKS_TOKEN  = shell_script.pat_token.output["token_value"]
    secret_scope_name = shell_script.secret_scope.output["name"]
    secret_name       = "datalake_sp_tenant"
    secret_value      = data.azuread_client_config.current.tenant_id
    debug_log         = true
  }

  depends_on = [
    azuread_service_principal_password.datalake
  ]
}

resource "shell_script" "upload_assets" {
  lifecycle_commands {
    create = "pwsh ${path.module}/scripts/upload.ps1 -type create"
    read   = "pwsh ${path.module}/scripts/upload.ps1 -type read"
    update = "pwsh ${path.module}/scripts/upload.ps1 -type update"
    delete = "pwsh ${path.module}/scripts/upload.ps1 -type delete"
  }

  environment = {
    DATABRICKS_HOST  = "https://${azurerm_resource_group.example.location}.azuredatabricks.net"
    DATABRICKS_TOKEN = shell_script.pat_token.output["token_value"]
    debug_log        = true
    upload_folder    = "${path.module}/assets"
    upload_dest      = "terraformassets"
  }
}


