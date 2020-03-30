param([String]$type)

# Terraform provider sends in current state
# as a json object to stdin
$stdin = $input

# Constants 
#
# This is the Azure AD application ID of the global databricks application 
# this is constant for all tentants/subscriptions as owned by databricks team
$databricksGlobalApplicationID = "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d"
# This is the azure management endpoint used. Unless in soverien clouds will be constant
$azureManagementEndpoint = "https://management.core.windows.net/"

# Vars
# 
# Databricks workspace endpoint
$databricksWorkspaceEndpoint = $env:DATABRICKS_HOST
$patTokenName = $env:pat_token_name
# Like - /subscriptions/GUID-HERE/resourceGroups/osplatform/providers/Microsoft.Databricks/workspaces/lgtestus
$databricksWorkspaceID = $env:workspace_id

function create {
    Write-Host "Starting create"

    $headers = get-AuthHeaders
    # Generate a PAT token. Note the quota limit of 600 tokens.
    $response = Invoke-WebRequest $databricksWorkspaceEndpoint/api/2.0/token/create `
        -Headers $headers `
        -Method 'POST' `
        -ContentType 'application/json; charset=utf-8' `
        -Body "{`"comment`": `"$patTokenName`"}"

    test-response $response

    # Write out the token information to be stored in the Terraform state
    $token = $response.Content | ConvertFrom-Json

    Write-host @"
    {
        "token_id": "$($token.token_info.token_id)",
        "token_value": "$($token.token_value)"
    }
"@
}

function read {
    Write-Host "Starting read"

    $currentToken = $stdin | ConvertFrom-Json
    $tokenID = $currentToken.token_id

    $headers = get-AuthHeaders
    # Check the existing PAT tokens to see if ours already exists
    $response = Invoke-WebRequest $databricksWorkspaceEndpoint/api/2.0/token/list `
        -Headers $headers `
        -Method 'GET'

    $tokens = $response.Content | ConvertFrom-JSON | select-object -expandProperty token_infos

    foreach ($token in $tokens) {
        if ($token.token_id -eq $tokenID) {
            # Yes it exists lets return the original state JSON to go in tf state
            # as this contains the `token_value` where as the `list` endpoint doesn't
            # return this data
            $json = $currentToken | ConvertTo-Json
            Write-Host $json
            return
        }
    }

    Write-Error "Error tokenID '$tokenID' now found in workspace!"
    exit 1
}

function update {
    Write-Host "Starting update (calls delete then create)"
    delete
    create
}

function delete {
    Write-Host "Starting delete"


    $currentToken = $stdin | ConvertFrom-Json
    $tokenID = $currentToken.token_value

    $headers = get-AuthHeaders
    # Check the existing PAT tokens to see if ours already exists
    $response = Invoke-WebRequest $databricksWorkspaceEndpoint/api/2.0/token/delete `
        -Headers $headers `
        -Method 'POST' `
        -ContentType 'application/json; charset=utf-8' `
        -Body "{`"token_id`": `"$tokenID`"}"

    test-response $response
}

function test-response($response) {
    if ($response.StatusCode -ne 200) {
        Write-Error "Request failed. Status code: $($response.StatusCode) Body: $($response.RawContent)"
        exit 1
    }
}


function get-AuthHeaders {
    # Get a token for the global Databricks application.
    # The resource name is fixed and never changes.
    $tokenGlobalDatabricks = az account get-access-token --resource $databricksGlobalApplicationID --output json `
    | ConvertFrom-Json `
    | Select-Object -ExpandProperty accessToken 

    # Get a token for the Azure management API
    $tokenAzureManagement = az account get-access-token --resource $azureManagementEndpoint --output json `
    | ConvertFrom-Json `
    | Select-Object -ExpandProperty accessToken 

    return @{
        "Authorization"                            = "Bearer $tokenGlobalDatabricks"
        "X-Databricks-Azure-SP-Management-Token"   = $tokenAzureManagement 
        "X-Databricks-Azure-Workspace-Resource-Id" = $databricksWorkspaceID
    }
}

Switch ($type) {
    "create" { create }
    "read" { read }
    "update" { update }
    "delete" { delete }
}