param([String]$type)

if ($ENV:debug_log) {
    Start-Transcript -Path "./runs.$type.log"
}

# Terraform provider sends in current state
# as a json object to stdin
$stdin = $input

# Vars
# 
# Databricks workspace endpoint
$databricksWorkspaceEndpoint = $env:DATABRICKS_HOST
$patToken = $env:DATABRICKS_TOKEN
$runJson = $env:run_json

$headers = @{
    "Authorization" = "Bearer $patToken"
}

function Get-RunIDFromJson($json) {
    return $json | ConvertFrom-Json | Select-Object -ExpandProperty run_id
}

function create {
    write-output "Starting create"

    $response = Invoke-WebRequest $databricksWorkspaceEndpoint/api/2.0/jobs/runs/submit `
        -Headers $headers `
        -Method 'POST' `
        -ContentType 'application/json; charset=utf-8' `
        -Body $runJson 

    test-response $response

    $runId = Get-RunIDFromJSON $response

    # Wait for the notebook to run and mount the storage
    Wait-ForRunState $runId "SUCCESS"

    # Get the updated state for the resource
    # A read on the API returns different data which we need to track in state
    # such as the last updated time. 
    # https://docs.databricks.com/dev-tools/api/latest/secrets.html#list-secrets
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='Used by read func')]
    $stdin = $response
    
    read 

}

function read {
    write-output "Starting read"

    $runId = Get-RunIDFromJson $stdin

    $response = Invoke-WebRequest "$databricksWorkspaceEndpoint/api/2.0/jobs/runs/get?run_id=$runId" `
        -Headers $headers `
        -Method 'GET' `
        -ContentType 'application/json; charset=utf-8'

    test-response $response

    #Filter to Job_id, Run_id and state then return for storage in 
    # terraform state
    $response | Convertfrom-json | Select-object -Property job_id, run_id, state | ConvertTo-Json | write-output
}

function update {
    write-output "Starting update (calls delete then create)"
    # Delete the current job then recreate
    # Todo: Review for update
    delete
    create
}

function delete {
    write-output "Starting delete"

    $runId = Get-RunIDFromJSON $stdin

    $response = Invoke-WebRequest $databricksWorkspaceEndpoint/api/2.0/jobs/runs/delete `
        -Headers $headers `
        -Method 'POST' `
        -ContentType 'application/json; charset=utf-8' `
        -Body @"
        {
            "run_id": "$runID", 
        }
"@

    test-response $response
}

function test-response($response) {
    if ($response.StatusCode -ne 200) {
        Write-Error "Request failed. Status code: $($response.StatusCode) Body: $($response.RawContent)"
        exit 1
    }
}


function Wait-ForRunState($runId, $wantedState, $alternativeState) {
    if (!$runId) {
        Throw "Error: runId empty"
    }
    $state = ""
    do {
        try {
            # API Docs
            # https://docs.microsoft.com/en-us/azure/databricks/dev-tools/api/latest/jobs#--runs-get

            $response = Invoke-WebRequest "$databricksWorkspaceEndpoint/api/2.0/jobs/runs/get?run_id=$runId" `
                -Headers $headers `
                -Method 'GET' `
                -ContentType 'application/json; charset=utf-8'
    
            test-response $response

            # Output for debugging
            $response | ConvertFrom-Json | Select-Object -ExpandProperty "state" | write-output

            # Get the content of `state.result_state` from the json response
            $state = $response | ConvertFrom-Json | Select-Object -ExpandProperty "state" | Select-Object -ExpandProperty "result_state"

            write-output "State: $state"
        }
        catch {
            write-output "Failed to get run_id=$runId, retrying..."
        }
        Start-Sleep -Seconds 5    
    } until ($state -eq $wantedState -or $state -eq $alternativeState)

    write-output "Found run state. Have: $state Want: $wantedState or $alternativeState"
}


Switch ($type) {
    "create" { create }
    "read" { read }
    "update" { update }
    "delete" { delete }
}