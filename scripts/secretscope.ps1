param([String]$type)

if ($ENV:debug_log) {
    Start-Transcript -Path "./secretscope.$type.log"
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
$scopeInitialManagePrincipal = $env:initial_manage_principal

$headers = @{
    "Authorization" = "Bearer $patToken"
}

function Get-CurrentName {
    $currentState = $stdin | ConvertFrom-Json
    return $currentState.name
}

function create {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='$stdin used to pass between funcs. Todo refactor')]
    param()
    
    Write-Host  "Starting create"
    
    $response = Invoke-WebRequest $databricksWorkspaceEndpoint/api/2.0/secrets/scopes/create `
        -Headers $headers `
        -Method 'POST' `
        -ContentType 'application/json; charset=utf-8' `
        -Body @"
        {
            "scope": "$scopeName",
            "initial_manage_principal": "$scopeInitialManagePrincipal"
        }
"@

    test-response $response

    Write-Host  $response.Content

    $stdin =   @"
    {
        "name": "$scopeName"
    }
"@
    read
}

function read {
    Write-Host  "Starting read"

    $response = Invoke-WebRequest "$databricksWorkspaceEndpoint/api/2.0/secrets/scopes/list" `
        -Headers $headers `
        -Method 'GET' `
        -ContentType 'application/json; charset=utf-8'

    $scopes = $response.Content | ConvertFrom-JSON | select-object -expandProperty scopes

    $currentName = Get-CurrentName
    if (-not $currentName) {
        throw "Current name is empty in state"
    }

    foreach ($scope in $scopes) {
        if ($scope.name -eq $currentName) {
            $json = $scope | ConvertTo-Json
            Write-Host  "Found scope:"
            Write-Host  $json
            return
        }
    }

    Write-Error "'$currentName' not found in workspace!"
}

function update {
    Write-Host  "Starting update (calls delete then create)"
    delete
    create
}

function delete {
    Write-Host  "Starting delete"

    $currentName = Get-CurrentName

    $response = Invoke-WebRequest $databricksWorkspaceEndpoint/api/2.0/secrets/scopes/delete `
        -Headers $headers `
        -Method 'POST' `
        -ContentType 'application/json; charset=utf-8' `
        -Body "{`"scope`": `"$currentName`"}"

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