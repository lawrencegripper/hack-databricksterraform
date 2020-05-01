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

# Retrieve the new workspace URL added in a recent databricks release
# https://docs.microsoft.com/en-us/azure/databricks/release-notes/product/2020/april#unique-urls-for-each-azure-databricks-workspace
data "shell_script" "workspaceHack" {
	lifecycle_commands {
		read = "pwsh ${path.module}/../../scripts/workspace.ps1"
	}

  environment = {
    workspace_id    = azurerm_databricks_workspace.example.id
  }
}

# Create cluster
resource "shell_script" "pat_token" {
  lifecycle_commands {
    create = "pwsh ${path.module}/../../scripts/pat.ps1 -type create"
    read   = "pwsh ${path.module}/../../scripts/pat.ps1 -type read"
    update = "pwsh ${path.module}/../../scripts/pat.ps1 -type update"
    delete = "pwsh ${path.module}/../../scripts/pat.ps1 -type delete"
  }

  environment = {
    pat_token_name  = "tf_pat_token"
    workspace_id    = azurerm_databricks_workspace.example.id
    DATABRICKS_HOST = "https://${data.shell_script.workspaceHack.output["workspaceURL"]}"
    debug_log       = true
  }

  # triggers a force new update
  # This causes the resource to be recreated if the workspace has been recreated
	triggers = {
		when_value_changed = data.shell_script.workspaceHack.output["workspaceURL"]
	}
}

resource "shell_script" "cluster" {
  lifecycle_commands {
    create = "pwsh ${path.module}/../../scripts/cluster.ps1 -type create"
    read   = "pwsh ${path.module}/../../scripts/cluster.ps1 -type read"
    update = "pwsh ${path.module}/../../scripts/cluster.ps1 -type update"
    delete = "pwsh ${path.module}/../../scripts/cluster.ps1 -type delete"
  }

  working_directory = path.module

  environment = {
    DATABRICKS_HOST  = "https://${data.shell_script.workspaceHack.output["workspaceURL"]}"
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
        "autotermination_minutes": 10
    }
JSON
    ))
  }

  # triggers a force new update
  # This causes the resource to be recreated if the workspace has been recreated
	triggers = {
		when_value_changed = data.shell_script.workspaceHack.output["workspaceURL"]
	}
}

