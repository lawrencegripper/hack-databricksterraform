
# Test if the databricks workspace still exists to prevent errors when a workspace
#   has been removed manually or state if corrupted. 
#
# Todo: Maybe this call could be cached to speed things up but think it would be a very minor gain
#   for quite a bit of complexity
function Test-DBWorkspaceExists($workspaceID) {
    $output = az resource show --ids $workspaceID
    if ($LASTEXITCODE -eq 0) {
        return $true
    }

    Write-Host "Failed to retrieve workspace: $output"
    return $false
}