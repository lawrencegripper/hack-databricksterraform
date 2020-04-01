param([String]$type)

# Terraform provider sends in current state
# as a json object to stdin
$stdin = $input

# Added function for mocking
function Get-Stdin {
    return $stdin
}


function create {
    Write-Host "Starting create"

    $clusterDef = @"
    {
        "cluster_name": "my-cluster-t1",
        "spark_version": "6.4.x-scala2.11",
        "node_type_id": "$ENV:machine_sku",
        "spark_conf": {
          "spark.speculation": true
        },
        "num_workers": "$ENV:worker_nodes",
        "autotermination_minutes": 300
    }
"@
    
    # Template the cluster creation json
    Set-Content ./clustercreate.json -Value $clusterDef
    
    # Create the cluster
    $createResult = databricks clusters create --json-file ./clustercreate.json
    Test-ForDatabricksError $createResult

    # Write json to stdout for provider to pickup and store state in terraform 
    # importantly this allows us to track the `cluster_id` property for future read/update/delete ops
    write-host $createResult

    # Cleanup temp file
    Remove-Item -Path ./clustercreate.json

    $clusterID = Get-ClusterIDFromJSON $createResult
    Wait-ForClusterState $clusterID "RUNNING"
}

function read {
    Write-Host "Starting read"

    $clusterID = Get-ClusterIDFromTFState

    # Get the current status of the cluster
    $getResult = databricks clusters get --cluster-id $clusterID
    Test-ForDatabricksError $getResult
    
    # Output just the cluster ID to workaround an issue with complex objects https://github.com/scottwinkler/terraform-provider-shell/issues/32
    Write-host @"
    { "cluster_id": "$clusterID" }
"@
}

function update {
    Write-Host "Starting update"

    $clusterID = Get-ClusterIDFromTFState
    # Only allow edit on running/terminated clusters
    # https://docs.databricks.com/dev-tools/api/latest/clusters.html#edit
    Wait-ForClusterState $clusterID "RUNNING" "TERMINATED"


    $json = @"
    {
        "cluster_id": "$clusterID",
        "node_type_id": "$ENV:machine_sku",
        "num_workers": "$ENV:worker_nodes",
        "spark_version": "6.4.x-scala2.11",
        "autotermination_minutes": 300
    }
"@

    Set-Content ./clusterupdate.json -Value $json

    $updateResult = databricks clusters edit --json-file ./clusterupdate.json
    Test-ForDatabricksError $updateResult
    Write-Host $updateResult

    Wait-ForClusterState $clusterDef "RUNNING"
}

function delete {
    Write-Host "Starting delete"
    $clusterID = Get-ClusterIDFromTFState

    $deleteResult = databricks clusters delete --cluster-id $clusterID
    Test-ForDatabricksError $deleteResult
    
    Write-Host "Cluster deleted"

    Wait-ForClusterState $clusterDef "TERMINATED"
}

# Read the stdin passed in by provider. This is the JSON formatted current state of the object as known by 
# terraform. This allows us to get the `cluster_id` property. 
function Get-ClusterIDFromTFState {
    return Get-ClusterIDFromJSON(Get-Stdin)
}

function Get-ClusterIDFromJSON($json) {
    $clusterID = $json | Convertfrom-json | select-object -expandproperty cluster_id
    if (!$clusterID) {
        Throw "Failed to get ClusterID from state: $input"
    }
    Write-Host "Found ClusterID from Terraform state: $clusterID"
    return $clusterID
}

function Wait-ForClusterState($clusterID, $wantedState, $alternativeState) {
    if (!$clusterID) {
        Throw "Error: Cluster ID empty"
    }
    # Wait for cluster to be ready
    $state = ""
    do {
        $getResult = Get-ClusterByID $clusterID
        $state = $getResult | Convertfrom-json | select-object -expandproperty state
        Write-Host "Checking cluster state. Have: $state Want: $wantedState or $alternativeState. Sleeping for 5secs"
        Start-Sleep -Seconds 5    
    } until ($state -eq $wantedState -or $state -eq $alternativeState)

    Write-Host "Found cluster state. Have: $state Want: $wantedState or $alternativeState"
}

function Get-ClusterByID([string]$id) {
    return databricks clusters get --cluster-id $clusterID
}

function Test-ForDatabricksError($response) {
    # Todo - maybe improve
    # Currently CLI returns `Error: b'{"error_code":"INVALID_PARAMETER_VALUE","message":"Cluster 1 does not exist"}'` on an error, for example
    if (!$response) {
        Write-Error "Failed to execute Databricks CLI. Null response: $response"
        exit 1
    }

    if ($response -like "Error: *") {
        Write-Error "Failed to execute Databricks CLI. Error: $response"
        exit 1
    }
}

Switch ($type) {
    "create" { create }
    "read" { read }
    "update" { update }
    "delete" { delete }
}