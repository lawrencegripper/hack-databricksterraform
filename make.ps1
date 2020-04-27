task default -depends Test

task "test" -depends "InstallRequirements" -Description "Run unit tests for project" {
    & ./scripts/cluster.tests.ps1
}

task "integrationTest" -depends "InstallRequirements" -Description "Create real cluster in Azure and assert correctly created" {
    & ./scripts/integration_tests.ps1
}

task "installRequirements" {
    & ./scripts/install_requirements.ps1
}

task "clean" {
    Get-Item "*.*.log" | Remove-Item
}

task "debugSecret" -depends "clean" {
    terraform state rm shell_script.secret
    terraform apply -auto-approve -var group_name=test1
}

task "checks" -depends "installRequirements", "clean" {
    Write-Host ">> Terraform verion"
    terraform -version 

    Write-Host ">> Terraform Format (if this fails use 'terraform fmt' command to resolve"
    terraform fmt -recursive -diff -check

    Write-Host ">> tflint"
    tflint

    Write-Host ">> Terraform init"
    terraform init

    Write-Host ">> Terraform validate"
    terraform validate
}