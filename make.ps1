task default -depends "checks", "test"

task "test" -depends "InstallRequirements" -Description "Run unit tests for project" {
    exec { & ./scripts/cluster.tests.ps1 }
}

task "integrationTest" -depends "InstallRequirements" -Description "Create real cluster in Azure and assert correctly created" {
    exec { & ./scripts/integration_tests.ps1 }
}

task "installRequirements" {
    exec { & ./scripts/install_requirements.ps1 }
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
    $saResults = Invoke-ScriptAnalyzer -Path ./scripts -Recurse -Settings PSGallery 
    if ($saResults) {
        $saResults | Format-Table  
        Write-Error -Message 'One or more Script Analyzer errors/warnings where found. Build cannot continue!'        
    }

    Write-Host  ">> Terraform verion"
    exec { terraform -version }

    Write-Host  ">> Terraform Format (if this fails use 'terraform fmt' command to resolve"
    exec { terraform fmt -recursive -diff -check }

    Write-Host  ">> tflint"
    exec { tflint }

    Write-Host  ">> Terraform init"
    exec { terraform init }

    Write-Host  ">> Terraform validate"
    exec { terraform validate }
}

task "ci" {
    exec { & docker build -f ./.devcontainer/Dockerfile ./.devcontainer -t localdevcontainer:latest }
    exec { & docker run -v ${PWD}:${PWD} -v /var/run/docker.sock:/var/run/docker.sock --workdir "${PWD}" --entrypoint /bin/bash -t localdevcontainer:latest -c "pwsh -c 'Invoke-psake ./make.ps1; exit (!`$psake.build_success)'" }
}