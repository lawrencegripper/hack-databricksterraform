$scriptDir = Split-Path -parent $PSCommandPath
Set-Location $scriptDir

function Get-ResourceState($resources, $address) {
    return $resources | Where-Object { $_.address -eq $address }
}

Describe "Terraform Deployment" { 
    Context "with clean tfstate" {
        Remove-Item ./terraform.tfstate -Force

        # Run terraform
        Write-Host "Applying terraform from scratch"

        terraform apply -auto-approve
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
            $cluster.values.output.cluster_id | Should -Not -BeNullOrEmpty
            $response = databricks clusters get --cluster-id $cluster.values.output.cluster_id | ConvertFrom-Json 
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
            $LASTEXITCODE | Should -Be 0

            if ($LASTEXITCODE -ne 0) {
                Write-Host "Detected terraform changes:"
                terraform show plan.tfstate
            }
        }
        
    }
}
