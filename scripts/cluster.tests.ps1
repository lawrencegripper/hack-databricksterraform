$scriptDir = Split-Path -parent $PSCommandPath
Set-Location $scriptDir

. ./cluster.ps1

Describe "Test-ForDatabricksError" {
    It "throws when empty response" {
        { Test-ForDatabricksError "" } | Should -Throw
    }

    It "throws when response contains error" {
        { Test-ForDatabricksError "Error: something failed" } | Should -Throw
    }

    It "throws when response is invalid json" {
        { Test-ForDatabricksError "jammydodgers" } | Should -Throw
    }
}

Describe "Get-ClusterIDFromTFState" {
    It "returns error when invalid state" {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='Used by the code under test')]
        $stdin = "invalidState"
        { Get-ClusterIDFromTFState } | Should -Throw 
    }

    It "returns ID for valid state" {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='Used by the code under test')]
        $stdin = "{ 'cluster_id': 'bob' }"
        Get-ClusterIDFromTFState | Should -BeExactly "bob"
    }
}

Describe "Get-ClusterIDFromJSON" {
    It "returns error when invalid state" {
        { Get-ClusterIDFromJSON "invalidState" } | Should -Throw 
    }

    It "returns ID for valid state" {
        Get-ClusterIDFromJSON "{ 'cluster_id': 'bob' }" | Should -BeExactly "bob"
    }
}

Describe "Wait-ForClusterState" {
    Context "With mocked write-output and start-sleep" {
        Mock write-output { }
        Mock Start-Sleep { }

    
        It "returns error when invalid clusterID passed" {
            { Wait-ForClusterState "" "pending" } | Should -Throw 
        }

        It "returns correctly when in RUNNING state" {
            $expectedLine1 = "Checking cluster state. Have: RUNNING Want: RUNNING or . Sleeping for 5secs"
            $expectedLine2 = "Found cluster state. Have: RUNNING Want: RUNNING or "
            
            $runningCluster = "{ 'state': 'RUNNING'}"
            Mock Invoke-DatabricksCLI { return $runningCluster }

            Wait-ForClusterState -clusterID "bob" -wantedState "RUNNING"

            Assert-MockCalled `
                -CommandName write-output `
                -Times 2 `
                -ParameterFilter { 
                $Object -eq $expectedLine1 -or $Object -eq $expectedLine2 
            } 
        }

        It "returns correctly when in TERMINATED state" {
            $expectedLine1 = "Checking cluster state. Have: TERMINATED Want: RUNNING or TERMINATED. Sleeping for 5secs"
            $expectedLine2 = "Found cluster state. Have: TERMINATED Want: RUNNING or TERMINATED"
            
            $terminatedCluster = "{ 'state': 'TERMINATED'}"
            Mock Invoke-DatabricksCLI { return $terminatedCluster }

            Wait-ForClusterState -clusterID "bob" -wantedState "RUNNING" -alternativeState "TERMINATED"

            Assert-MockCalled `
                -CommandName write-output `
                -Times 2 `
                -ParameterFilter { 
                $Object -eq $expectedLine1 -or $Object -eq $expectedLine2 
            } 
        }
    }
}