$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'ApplicationRole', 'DefaultSchema', 'Password', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $instance = Connect-DbaInstance -SqlInstance $script:instance2
        $dbname = "dbatoolsci_adddb_newapprole"
        $instance.Query("create database $dbname")
        $role1 = "dbExecuter"
        $role2 = "dbSPAccess"
        $password = ConvertTo-SecureString "P@ssW0rD!" -AsPlainText -Force
    }
    AfterEach {
        #$null = Remove-DbaDbRole -SqlInstance $instance -Database $dbname -Role $role1, $role2 -Confirm:$false
    }
    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $instance -Database $dbname -Confirm:$false
    }

    Context "Functionality" {
        It 'Add new role and returns results' {
            $params = @{
                SqlInstance = $instance
                Database = $dbname
                ApplicationRole = $role1
                Password = $password
            }
            $result = New-DbaDbApplicationRole @params

            $result.Count | Should Be 1
            $result.Name | Should Be $role1
            $result.Parent | Should Be $dbname
        }

        It 'Add two new roles and returns results' {
            $params = @{
                SqlInstance = $instance
                Database = $dbname
                ApplicationRole = @($role1, $role2)
                Password = $password
            }
            $result = New-DbaDbApplicationRole @params

            $result.Count | Should Be 2
            $result.Name | Should Contain $role1
            $result.Name | Should Contain $role2
            $result.Parent | Select-Object -Unique | Should Be $dbname
        }

        It 'Accept database as inputObject' {
            $result = $instance.Databases[$dbname] | New-DbaDbRole -Role $role1 -Password $password

            $result.Count | Should Be 1
            $result.Name | Should Be $role1
            $result.Parent | Should Be $dbname
        }
    }
}