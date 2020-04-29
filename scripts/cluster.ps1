param([String]$type)

if ($ENV:debug_log) {
    Start-Transcript -Path "./cluster.$type.log"
}

# Terraform provider sends in current state
# as a json object to stdin
$stdin = $input

# DatabricksCLI
function Invoke-DatabricksCLI {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Scope = 'Function', Justification = 'Todo revisit this and find alternative')]
    param($command)

    Invoke-Expression $command
}


function create {
    Write-Host  "Starting create"

    $clusterDef = $ENV:cluster_json
    
    # Template the cluster creation json
    Set-Content ./clustercreate.json -Value $clusterDef
    
    # Create the cluster. Handle intermittent failures via retry.
    $createComplete = $false
    $retryCount = 0
    while (-not $createComplete) {
        try {
            $createResult = databricks clusters create --json-file ./clustercreate.json
            Test-ForDatabricksError $createResult
            $createComplete = $true
        }
        catch {
            if ($retryCount -ge 10) {
                throw
            }
            else {
                Write-Host  "Create failed. Retrying after wait..."
                Start-Sleep -Seconds 10
            }
        }
        $retryCount++
    }
    
    # Cleanup temp file
    Remove-Item -Path ./clustercreate.json
    
    $clusterID = Get-ClusterIDFromJSON $createResult
    $waitForState = "RUNNING"
    if ($ENV:wait_for_state) {
        $waitForState = $ENV:wait_for_state
    }
    Wait-ForClusterState -clusterID $clusterID -wantedState $waitForState

    # Write json to stdout for provider to pickup and store state in terraform 
    # importantly this allows us to track the `cluster_id` property for future read/update/delete ops
    Write-Host  $createResult
}

function read {
    Write-Host  "Starting read"

    $clusterID = Get-ClusterIDFromTFState

    # Get the current status of the cluster
    $getResult = databricks clusters get --cluster-id $clusterID
    Test-ForDatabricksError $getResult
    
    # Output just the cluster ID to workaround an issue with complex objects https://github.com/scottwinkler/terraform-provider-shell/issues/32
    Write-Host  @"
    { "cluster_id": "$clusterID" }
"@
}

function update {
    Write-Host  "Starting update"

    $clusterID = Get-ClusterIDFromTFState
    # Only allow edit on running/terminated clusters
    # https://docs.databricks.com/dev-tools/api/latest/clusters.html#edit
    Wait-ForClusterState -clusterID $clusterID -wantedState "RUNNING" -alternativeState "TERMINATED"


    $json = $ENV:cluster_json

    # Add cluster_id property required for edits
    $clusterDef = $json | ConvertFrom-Json
    $clusterDef | add-member -NotepropertyName "cluster_id" -NotePropertyValue $clusterID
    $json = $clusterDef | ConvertTo-Json

    Set-Content ./clusterupdate.json -Value $json

    $updateResult = databricks clusters edit --json-file ./clusterupdate.json
    Test-ForDatabricksError $updateResult
    Write-Host  $updateResult

    Wait-ForClusterState -clusterID $clusterDef -wantedState "RUNNING"
}

function delete {
    Write-Host  "Starting delete"
    $clusterID = Get-ClusterIDFromTFState

    $deleteResult = databricks clusters delete --cluster-id $clusterID
    if ($deleteResult -like "Error: *") {
        Throw "Failed to execute Databricks CLI. Error: $response"
    }
    
    Write-Host  "Cluster deleted"

    Wait-ForClusterState -clusterID $clusterDef -wantedState "TERMINATED"
}

# Read the stdin passed in by provider. This is the JSON formatted current state of the object as known by 
# terraform. This allows us to get the `cluster_id` property. 
function Get-ClusterIDFromTFState {
    return Get-ClusterIDFromJSON($stdin)
}

function Get-ClusterIDFromJSON($json) {
    $clusterID = $json | Convertfrom-json | select-object -expandproperty cluster_id
    if (!$clusterID) {
        Throw "Failed to get ClusterID from state: $input"
    }
    Write-Host  "Found ClusterID from Terraform state: $clusterID"
    return $clusterID
}

function Wait-ForClusterState($clusterID, $wantedState, $alternativeState) {
    $ErrorActionPreference = "Stop"

    if (!$clusterID) {
        Throw "Error: Cluster ID empty"
    }
    # Wait for cluster to be ready
    $state = "local_not_set_state"
    do {
        try {
            $getResult = Invoke-DatabricksCLI "databricks clusters get --cluster-id $clusterID"
            Test-ForDatabricksError $getResult

            $state = $getResult | Convertfrom-json | select-object -expandproperty state
            Write-Host "Checking cluster state. Have: $state Want: $wantedState or $alternativeState. Sleeping for 5secs"
        }
        catch {
            Write-Host "Failed to get $clusterID, retrying..."
        }
        Start-Sleep -Seconds 5    
    } until ($state -eq $wantedState -or $state -eq $alternativeState)

    Write-Host  "Found cluster state. Have: $state Want: $wantedState or $alternativeState"
}

function Test-ForDatabricksError($response) {
    # Todo - maybe improve
    # Currently CLI returns `Error: b'{"error_code":"INVALID_PARAMETER_VALUE","message":"Cluster 1 does not exist"}'` on an error, for example
    if (!$response) {
        Throw "Failed to execute Databricks CLI. Null response: $response"
    }
    
    if ($response -like "Error: *") {
        Write-Host  "CLI Response: $response"
        Throw "Failed to execute Databricks CLI. Error response."
    }

    try {
        $response | ConvertFrom-Json
    }
    catch {
        Write-Host  "Failed to execute Databricks CLI. Invalid Json response. CLI Response: $response"
        Throw 
    }
}

Switch ($type) {
    "create" { create }
    "read" { read }
    "update" { update }
    "delete" { delete }
}