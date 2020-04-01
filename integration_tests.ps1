$scriptDir = Split-Path -parent $PSCommandPath
Set-Location $scriptDir

function Get-ResourceState($resources, $address) {
    return $resources | Where-Object { $_.address -eq $address }
}

Describe "Terraform Deployment" { 
    Context "with clean tfstate" {
        # Remove state so no resources current tracked by tf
        Remove-Item ./terraform.tfstate -Force

        # Set variables for Terraform
        $randomGroupNum = Get-Random
        $ENV:TF_VAR_group_name = "inttest$randomGroupNum"

        Write-Host "Using ResourceGroup: $ENV:TF_VAR_group_name"

        # Run terraform
        Write-Host "Applying terraform from scratch"
        $tfOutput = terraform apply -auto-approve
        Write-Host $tfOutput
        $LASTEXITCODE | Should -Be 0

        Write-Host "terraform apply completed"
    
        # Get state after `terraform apply`
        $tfState = terraform show -json | ConvertFrom-Json
        $resources = $tfState.values.root_module.resources 

        #Created Resources
        $workspace = Get-ResourceState $resources "azurerm_databricks_workspace.example"
        $patToken = Get-ResourceState $resources "shell_script.pat_token"
        $cluster = Get-ResourceState $resources "shell_script.cluster"


        It "returns state for all resources" {
            $workspace | Should -Not -BeNullOrEmpty
            $patToken | Should -Not -BeNullOrEmpty
            $cluster | Should -Not -BeNullOrEmpty
        }

        It "returns a valid azure resource for the workspace" {
            $workspace.values.id | Should -Not -BeNullOrEmpty
            az resource show --ids $workspace.values.id
            $LASTEXITCODE | Should -Be 0
        }

        It "returns a valid running cluster" {
            $cluster.values.output.cluster_id | Should -Not -BeNullOrEmpty -Because "cluster_id should be stored in state"

            # Setup auth for databrickscli
            $ENV:DATABRICKS_HOST = "https://$($workspace.values.location).azuredatabricks.net"
            $ENV:DATABRICKS_TOKEN = $patToken.values.output.token_value
            
            # Attempt to get the cluster
            $responseRaw = databricks clusters get --cluster-id $cluster.values.output.cluster_id
            { $responseRaw | ConvertFrom-Json } | Should -Not -Throw -Because "Valid json should be returned by the databricks cli"

            $response = $responseRaw | ConvertFrom-Json
            $response.state | Should -Be "RUNNING"
        }

        It "returns an empty plan when re-run" {
            # Run a terraform plan and check no changes are detected
            # `-detailed-exitcode` will cause the command to exit with 0 exit code
            # only if there are no diffs in the plan 
            # https://www.terraform.io/docs/commands/plan.html#detailed-exitcode
            #
            # If this test fails it shows an issue with the `read` command returning different data between calls.
            Write-Host "Running terraform plan"

            terraform plan -out plan.tfstate -detailed-exitcode
            
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Detected terraform changes:"
                terraform show plan.tfstate
            }

            $LASTEXITCODE | Should -Be 0 -Because "plan should show no changes"
        }
    }
}

Describe "Terraform Destroy" { 
    Context "with existing tfstate" {
        # Ensure we have an existing terraform deployment
        "./terraform.tfstate" | Should -Exist

        # Get state before the `terraform destroy` so we can check 
        # resources have been removed correctly
        $tfState = terraform show -json | ConvertFrom-Json
        $resources = $tfState.values.root_module.resources 

        #Created Resources
        $workspace = Get-ResourceState $resources "azurerm_databricks_workspace.example"
        $patToken = Get-ResourceState $resources "shell_script.pat_token"
        $cluster = Get-ResourceState $resources "shell_script.cluster"
        $resourceGroup = Get-ResourceState $resources "azurerm_resource_group.example"

        It "check we captured state for all resources before deletes" {
            $workspace | Should -Not -BeNullOrEmpty
            $patToken | Should -Not -BeNullOrEmpty
            $cluster | Should -Not -BeNullOrEmpty
        }

        It "destroy the cluster and check it's terminated" {
            Write-host "Destroying terraform"
            $tfOutput = terraform destroy -auto-approve -target='shell_script.cluster'
            $LASTEXITCODE | Should -Be 0

            Write-Host $tfOutput

            $cluster.values.output.cluster_id | Should -Not -BeNullOrEmpty
            
            $ENV:DATABRICKS_HOST = "https://$($workspace.values.location).azuredatabricks.net"
            $ENV:DATABRICKS_TOKEN = $patToken.values.output.token_value

            $response = databricks clusters get --cluster-id $cluster.values.output.cluster_id | ConvertFrom-Json 
            $response.state | Should -Be "TERMINATED"
        }

        It "cleans up whole resourcegroup" {
            az resource delete --ids $resourceGroup.values.id
            $LASTEXITCODE | Should -Be 0
        }
    }
}
