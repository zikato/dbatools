$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'Role', 'ExcludeRole', 'IncludeSystemDbs', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $role1 = "dbatoolssci_role1_$(Get-Random)"
        $role2 = "dbatoolssci_role2_$(Get-Random)"
        $dbname1 = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $script:instance2 -Name $dbname1 -Owner sa

        $roleNames = @('Role1', 'Rol2')

        $null = New-DbaDbApplicationRole -SqlInstance $script:instance2 -SqlCredential $script:instance1cred -Database $dbname1 -ApplicationRole $roleNames
    }
    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbname1 -confirm:$false
    }

    Context "Functionality" {
        It 'Accepts a list of roles' {
            $result0 = Get-DbaDbApplicationRole -SqlInstance $script:instance2 -Database $dbname1 -ApplicationRole $role1, $role2
            Remove-DbaDbApplicationRole -SqlInstance $script:instance2 -Database $dbname1 -Role $role1 -confirm:$false
            $result1 = Get-DbaDbApplicationRole -SqlInstance $script:instance2 -Database $dbname1

            $result0.Count | Should BeGreaterThan $result1.Count
            $result1.Name -contains $role1  | Should Be $false
            $result1.Name -contains $role2  | Should Be $true
        }
    }
}