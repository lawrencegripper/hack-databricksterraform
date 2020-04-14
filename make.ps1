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