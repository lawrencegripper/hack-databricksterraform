param([String]$type)

if ($ENV:debug_log) {
    Start-Transcript -Path "./secret.$type.log"
}

# Terraform provider sends in current state
# as a json object to stdin
$stdin = $input

# Vars
# 
# Databricks workspace endpoint
$databricksWorkspaceEndpoint = $env:DATABRICKS_HOST
$patToken = $env:DATABRICKS_TOKEN
$scopeName = $env:secret_scope_name
$secretName = $env:secret_name
$secretValue = $env:secret_value

$headers = @{
    "Authorization" = "Bearer $patToken"
}

function Get-CurrentKey {
    $currentState = $stdin | ConvertFrom-Json
    return $currentState.key
}

function create {
    Write-Host "Starting create"
    
    $secret = @"
        {
            "scope": "$scopeName",
            "key": "$secretName",
            "string_value": "$secretValue"
        }
"@

    $response = Invoke-WebRequest $databricksWorkspaceEndpoint/api/2.0/secrets/put `
        -Headers $headers `
        -Method 'POST' `
        -ContentType 'application/json; charset=utf-8' `
        -Body $secret 

    test-response $response

    # Get the updated state for the resource
    # A read on the API returns different data which we need to track in state
    # such as the last updated time. 
    # https://docs.databricks.com/dev-tools/api/latest/secrets.html#list-secrets
    $stdin = $secret
    read 
}

function read {
    Write-Host "Starting read"

    $response = Invoke-WebRequest "$databricksWorkspaceEndpoint/api/2.0/secrets/list?scope=$scopeName" `
        -Headers $headers `
        -Method 'GET' `
        -ContentType 'application/json; charset=utf-8'

    $secrets = $response.Content | ConvertFrom-JSON | select-object -expandProperty secrets

    $currentKey = Get-CurrentKey
    foreach ($secret in $secrets) {
        if ($secret.key -eq $currentKey) {
            $json = $secret | ConvertTo-Json
            Write-Host "Found secret:"
            Write-Host $json
            return
        }
    }

    Write-Error "'$name' not found in workspace!"
}

function update {
    Write-Host "Starting update (calls delete then create)"
    # No need for delete as `create` is a put so will update the secret
    # https://docs.databricks.com/dev-tools/api/latest/secrets.html#put-secret
    create
}

function delete {
    Write-Host "Starting delete"

    $currentKey = Get-CurrentKey

    $response = Invoke-WebRequest $databricksWorkspaceEndpoint/api/2.0/secrets/delete `
        -Headers $headers `
        -Method 'POST' `
        -ContentType 'application/json; charset=utf-8' `
        -Body @"
        {
            "scope": "$scopeName", 
            "key": "$currentKey"
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

Switch ($type) {
    "create" { create }
    "read" { read }
    "update" { update }
    "delete" { delete }
}