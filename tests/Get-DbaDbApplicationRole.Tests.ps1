$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'ApplicationRole', 'ExcludeApplicationRole', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $instance = Connect-DbaInstance -SqlInstance $script:instance2 -SqlCredential $script:instance1cred
        $allDatabases = $instance.Databases

        $dbname1 = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $script:instance2 -Name $dbname1 -Owner sa

        $roleNames = @('Role1', 'Rol2')

        $null = New-DbaDbApplicationRole -SqlInstance $script:instance2 -SqlCredential $script:instance1cred -Database $dbname1 -ApplicationRole $roleNames
    }

    Context "Functionality" {
        It 'Returns Results' {
            $result = Get-DbaDbApplicationRole -SqlInstance $instance -SqlCredential $script:instance1cred

            $result.Count | Should Be $roleNames.Count
        }

        It 'Returns all role membership for all databases' {
            $result = Get-DbaDbApplicationRole -SqlInstance $instance -SqlCredential $script:instance1cred

            $uniqueDatabases = $result.Database | Select-Object -Unique
            $uniqueDatabases.Count | Should -BeExactly $roleNames.Count
        }

        It 'Accepts a list of roles' {
            $result = Get-DbaDbApplicationRole -SqlInstance $instance -SqlCredential $script:instance1cred -ApplicationRole $roleNames

            'Role1' | Should -BeIn $result.Name
            'Role2' | Should -BeIn $result.Name
        }
    }
}