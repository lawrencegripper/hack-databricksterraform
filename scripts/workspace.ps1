# if ($ENV:debug_log) {
    Start-Transcript -Path "./workspace.data.log"
# }

# Like - /subscriptions/GUID-HERE/resourceGroups/osplatform/providers/Microsoft.Databricks/workspaces/lgtestus
$databricksWorkspaceID = $env:workspace_id

$workspaceURL = az resource show --id $databricksWorkspaceID --query properties.workspaceUrl --output tsv
if ($LASTEXITCODE -ne 0) {
    throw "Azure CLI returned an error."
}

Write-Host @"
  { "workspaceURL": "$workspaceURL" }
"@