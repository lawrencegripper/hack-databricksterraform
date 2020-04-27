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

task "fixup" {
    terraform fmt -recursive
    Invoke-ScriptAnalyzer -Path ./scripts -Recurse -Settings PSGallery -Fix 
}

task "checks" -depends "installRequirements", "clean" {
    Write-Host  ">> Powershell Script Analyzer"
    Invoke-ScriptAnalyzer -Path ./scripts -Recurse -Settings PSGallery -EnableExit

    Write-Host  ">> Terraform verion"
    terraform -version 

    Write-Host  ">> Terraform Format (if this fails use 'terraform fmt' command to resolve"
    terraform fmt -recursive -diff -check

    Write-Host  ">> tflint"
    tflint

    Write-Host  ">> Terraform init"
    terraform init

    Write-Host  ">> Terraform validate"
    terraform validate
}

task "ci" {
    docker build -f ./.devcontainer/Dockerfile ./.devcontainer -t localdevcontainer:latest

    docker run -v ${PWD}:${PWD} -v /var/run/docker.sock:/var/run/docker.sock --workdir "${PWD}" --entrypoint /bin/bash -t localdevcontainer:latest -c "pwsh -c 'Invoke-psake ./make.ps1 ci'"

}