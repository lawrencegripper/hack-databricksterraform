$scriptDir = Split-Path -parent $PSCommandPath
Set-Location "$scriptDir"

function Get-ResourceState($resources, $address) {
    return $resources | Where-Object { $_.address -eq $address }
}

# There is a class of error in which the shell_provider code expects to find resources
# in the databricks workspace and cannot. In this case it should trigger them to be recreated. 
# This test catches bugs that instead cause terraform to error when this occurs. 
Describe "Terraform Deployment then taint and recreate workspace" { 
    
    Context "with clean tfstate" {
        # Remove state so no resources current tracked by tf
        Remove-Item ./terraform.tfstate -Force

        # Initilize terraform
        terraform init

        # Set variables for Terraform
        $randomGroupNum = Get-Random
        $ENV:TF_VAR_group_name = "inttest$randomGroupNum"

        Write-Host  "Using ResourceGroup: $ENV:TF_VAR_group_name"

        Write-Host  "Applying terraform from scratch. Tail testTFAapply.1.log to see progress"
        $tfOutput = terraform apply -auto-approve | Tee-Object -FilePath testTFApply.1.log
        Write-Host  $tfOutput
        $LASTEXITCODE | Should -Be 0

        Write-Host  "terraform apply completed"
    
        # Get state after `terraform apply`
        $tfState = terraform show -json | ConvertFrom-Json
        $resources = $tfState.values.root_module.resources 

        Write-Host  "Taint the workspace to mark for recreation"
        $tfOutput = terraform taint "azurerm_databricks_workspace.example"
        Write-Host  $tfOutput
        $LASTEXITCODE | Should -Be 0

        Write-Host  "Run Apply to remove and recreate workspace. Tail testTFAapply.2.log to see progress"
        $tfOutput = terraform apply -auto-approve | Tee-Object -FilePath testTFApply.2.log
        Write-Host  $tfOutput
        $LASTEXITCODE | Should -Be 0

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
            if ($cluster.values.environment.wait_for_state) {
                $response.state | Should -Be $cluster.values.environment.wait_for_state
            }
            else {
                $response.state | Should -Be "RUNNING"
            }
        }

        It "returns an empty plan when re-run" {
            # Run a terraform plan and check no changes are detected
            # `-detailed-exitcode` will cause the command to exit with 0 exit code
            # only if there are no diffs in the plan 
            # https://www.terraform.io/docs/commands/plan.html#detailed-exitcode
            #
            # If this test fails it shows an issue with the `read` command returning different data between calls.
            Write-Host  "Running terraform plan"

            # Sleep for a bit to simluate a delay between plan runs. This will assist in capturing a class 
            # of bug in which the API response contains a timestamp which is accidentally persisted into the state file.
            start-sleep -seconds 15

            terraform plan -out plan.tfstate -detailed-exitcode | Tee-Object -FilePath testTFPlan.1.log
            
            if ($LASTEXITCODE -ne 0) {
                Write-Host  "Detected terraform changes:"
                terraform show plan.tfstate
            }

            $LASTEXITCODE | Should -Be 0 -Because "plan should show no changes"
        }

        It "destroy the cluster and check it's terminated" {
            Write-Host  "Destroying terraform"
            $tfOutput = terraform destroy -var group_name=$resourceGroup.values.name -auto-approve -target='shell_script.cluster'
            $LASTEXITCODE | Should -Be 0

            Write-Host  $tfOutput

            $cluster.values.output.cluster_id | Should -Not -BeNullOrEmpty
            
            $ENV:DATABRICKS_HOST = "https://$($workspace.values.location).azuredatabricks.net"
            $ENV:DATABRICKS_TOKEN = $patToken.values.output.token_value

            $response = databricks clusters get --cluster-id $cluster.values.output.cluster_id | ConvertFrom-Json 
            $response.state | Should -BeLike "TERMINAT*" -Because "Should either be terminated or terminating"
        }

        It "cleans up whole resource group" {
            az group delete --name $resourceGroup.values.name  --no-wait -y
            $LASTEXITCODE | Should -Be 0
        }
    }
}