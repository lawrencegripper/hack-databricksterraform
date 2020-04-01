# Disclaimer

This is a point in time hack and isn't kept up-to-date. It best serves as a guide or sample.

## What does it do?

Creates a:
1. Databricks workspace in Azure
1. PAT token for accessing Databricks API
1. Cluster in Databricks workspace
1. Store the `cluster_id` and `pat_token` between runs in Terraform `state`

# Run 

1. Have `azurecli` installed and logged in, have `python3` and `pip3` installed.
1. Run `powershell ./install_requirements.ps1`
1. Run `terraform apply -auto-approve -var 'group_name=yourGroupNameHere'` (run `terraform plan` first if you want to see what will be created)
1. See cluster created

# Dev 

The repo includes VSCode devcontainer. Clone and open the code in VSCode and enable the devcontainer. 

Info: https://code.visualstudio.com/docs/remote/containers

# Debug

## Cleanup

`databricks clusters list | awk '{print $1}' | xargs -n 1 databricks clusters delete --cluster-id`

## Logs

### Option 1 

Set `debug_log` to `true` in the terraform resource you want to debug and you'll get `cluster.[create|read|update|delete].logs` files appear after the provider executes.

```terraform
  environment = {
    debug_log        = true
  }
```

### Option 2

Set `TF_LOG=debug` then re-run the `terraform apply`. Logs like the following will be visible to show you what has happened when the scripts executed.

For example here is some output when the script path is incorrect:

```
-------------------------
[DEBUG] Command execution completed:
-------------------------
[DEBUG] no JSON strings found in stdout
[DEBUG] Unlocking "shellScriptMutexKey"
[DEBUG] Unlocked "shellScriptMutexKey"
[DEBUG] Reading shell script resource...
-------------------------
[DEBUG] Current stack:
[DEBUG] -- create
[DEBUG] -- read
-------------------------
[DEBUG] Locking "shellScriptMutexKey"
[DEBUG] Locked "shellScriptMutexKey"
[DEBUG] shell script command old state: "&{[DATABRICKS_HOST=https://eastus.azuredatabricks.net machine_sku=Standard_D3_v2 worker_nodes=8 DATABRICKS_TOKEN=ATOKENMIGHTBEHERE] map[]}"
[DEBUG] shell script going to execute: /bin/sh -c
   pwsh -command '& { . ./cluster.ps1; read }'
-------------------------
[DEBUG] Starting execution...
-------------------------
  .: The term './cluster.ps1' is not recognized as the name of a cmdlet, function, script file, or operable program.
  Check the spelling of the name, or if a path was included, verify that the path is correct and try again.
  read: The term 'read' is not recognized as the name of a cmdlet, function, script file, or operable program.
  Check the spelling of the name, or if a path was included, verify that the path is correct and try again.
```