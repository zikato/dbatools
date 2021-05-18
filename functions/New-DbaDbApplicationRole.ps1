function New-DbaDbApplicationRole {
    <#
    .SYNOPSIS
        Create new database application roles for each database(s)/ instance(s) of SQL Server.

    .DESCRIPTION
        The New-DbaDbRole create new application roles on database(s)/ instance(s) of SQL Server.

   .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. This list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER ApplicationRole
        The role(s) to create.

    .PARAMETER InputObject
        Enables piped input from Get-DbaDatabase

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ApplicationRole, Database, Security
        Author: Sander Stad (@sqlstad), https://sqlstad.nl
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaDbApplicationRole

    .EXAMPLE
        PS C:\> New-DbaDbApplicationRole -SqlInstance sql2017a -Database db1 -ApplicationRole 'dbExecuter'

        Will create a new role named dbExecuter within db1 on sql2017a instance.

    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]

    param(
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$ApplicationRole,
        [pscredential]$Password,
        [string]$DefaultSchema,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        if (-not $DefaultSchema) {
            $DefaultSchema = 'dbo'
        }

        if (-not $Password) {
            Stop-Function -Message "You must specify a password to create the application role"
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a database or specify a SqlInstance."
            return
        }

        if (-not $ApplicationRole) {
            Stop-Function -Message "You must specify a new application role name."
            return
        }

        if ($SqlInstance) {
            foreach ($instance in $SqlInstance) {
                $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
            }
        }

        $InputObject = $InputObject | Where-Object { $_.IsAccessible -eq $true }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            Write-Message -Level 'Verbose' -Message "Getting Application Roles for $db on $server"

            $appRoles = $db.ApplicationRoles

            foreach ($role in $ApplicationRole) {
                if ($appRoles | Where-Object Name -eq $role) {
                    Stop-Function -Message "The $role application role already exist within database $db on instance $server." -Target $db -Continue
                }

                Write-Message -Level Verbose -Message "Add roles to Database $db on target $server"

                if ($Pscmdlet.ShouldProcess("Creating new ApplicationRole $role on database $db", $server)) {
                    try {
                        $newRole = New-Object -TypeName Microsoft.SqlServer.Management.Smo.ApplicationRole
                        $newRole.Name = $role
                        $newRole.Parent = $db
                        $newRole.DefaultSchema = $DefaultSchema

                        $newRole.Create($Password)

                        Add-Member -Force -InputObject $newRole -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                        Add-Member -Force -InputObject $newRole -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                        Add-Member -Force -InputObject $newRole -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                        Add-Member -Force -InputObject $newRole -MemberType NoteProperty -Name ParentName -value $db.Name

                        Select-DefaultView -InputObject $newRole -Property ComputerName, InstanceName, SqlInstance, Name, 'ParentName as Parent', DefaultSchema
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                    }
                }
            }
        }
    }


}