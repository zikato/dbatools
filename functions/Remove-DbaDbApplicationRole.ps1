function Remove-DbaDbApplicationRole {
    <#
    .SYNOPSIS
        Removes a database role from database(s) for each instance(s) of SQL Server.

    .DESCRIPTION
        The Remove-DbaDbApplicationRole removes role(s) from database(s) for each instance(s) of SQL Server.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. This list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude. This list is auto-populated from the server.

    .PARAMETER Role
        The role(s) to process. If unspecified, all roles will be processed.

    .PARAMETER ExcludeRole
        The role(s) to exclude.

    .PARAMETER IncludeSystemDbs
        If this switch is enabled, roles can be removed from system databases.

    .PARAMETER InputObject
        Enables piped input from Get-DbaDbApplicationRole or Get-DbaDatabase

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Role, Database, Security, Login
        Author: Ben Miller (@DBAduck)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbApplicationRole

    .EXAMPLE
        PS C:\> Remove-DbaDbApplicationRole -SqlInstance localhost -Database dbname -ApplicationRole "customrole1", "customrole2"

        Removes roles customrole1 and customrole2 from the database dbname on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Remove-DbaDbApplicationRole -SqlInstance localhost, sql2016 -Database db1, db2 -ApplicationRole role1, role2, role3

        Removes role1,role2,role3 from db1 and db2 on the local and sql2016 SQL Server instances

    .EXAMPLE
        PS C:\> $servers = Get-Content C:\servers.txt
        PS C:\> $servers | Remove-DbaDbApplicationRole -Database db1, db2 -Role role1

        Removes role1 from db1 and db2 on the servers in C:\servers.txt
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$ApplicationRole,
        [string[]]$ExcludeApplicationRole,
        [switch]$IncludeSystemDbs,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )

    process {
        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a database or specify a SqlInstance."
            return
        }

        if ($SqlInstance) {
            foreach ($instance in $SqlInstance) {
                $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
            }
        }

        $approles = @()
        foreach ($db in $InputObject) {
            Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject"

            $params = @{
                SqlInstance            = $input
                SqlCredential          = $SqlCredential
                Database               = $db
                ExcludeDatabase        = $ExcludeDatabase
                ApplicationRole        = $ApplicationRole
                ExcludeApplicationRole = $ExcludeApplicationRole
            }

            $appRoles += Get-DbaDbApplicationRole @params
        }

        foreach ($appRole in $appRoles) {
            $db = $appRole.Parent
            $instance = $db.Parent
            if ((!$db.IsSystemObject) -or ($db.IsSystemObject -and $IncludeSystemDbs )) {
                if ($PSCmdlet.ShouldProcess($instance, "Remove application role $appRole from database $db")) {
                    $schemas = $appRole.Parent.Schemas | Where-Object { $_.Owner -eq $appRole.Name }
                    if (!$schemas) {
                        $appRole.Drop()
                    } else {
                        Write-Message -Level warning -Message "Cannot remove role $appRole from database $db on instance $instance as it owns one or more Schemas"
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Can only remove roles from System database when IncludeSystemDbs switch used."
            }
        }
    }
}
