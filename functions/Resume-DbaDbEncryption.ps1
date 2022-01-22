function Resume-DbaDbEncryption {
    <#
    .SYNOPSIS
        Resumes decryption for one or more databases on an instance

    .DESCRIPTION
        Resumes decryption for one or more databases on an instance

        'master', 'model', 'tempdb', 'msdb', 'resource' are excluded by default

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential)

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported

        For MFA support, please use Connect-DbaInstance

    .PARAMETER Database
        The specific databases where encryption will be resumed

    .PARAMETER ExcludeDatabase
        The specific databases where encryption will not be resumed

        'master', 'model', 'tempdb', 'msdb', 'resource' are excluded by default

    .PARAMETER InputObject
        Allows piping from Get-DbaDatabase

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate, Security
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Resume-DbaDbEncryption

    .EXAMPLE
        PS C:\> Resume-DbaDbEncryption -SqlInstance sql01

        Resumes decryption for all databases on a SQL Server instance

        Prompts for confirmation along the way

    .EXAMPLE
        PS C:\> Resume-DbaDbEncryption -SqlInstance sql01 -Database db1 -Confirm:$false

        Resumes decryption for all databases on a SQL Server instance

        Does not prompt for confirmation along the way
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [Parameter(Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (-not $SqlInstance -and -not $InputObject) {
            Stop-Function -Message "Either -SqlInstance or -InputObject must be specified"
            return
        }
        if ($SqlInstance) {
            $param = @{
                SqlInstance     = $SqlInstance
                SqlCredential   = $SqlCredential
                Database        = $Database
                ExcludeDatabase = $ExcludeDatabase
            }
            $InputObject = Get-DbaDatabase @param | Where-Object Name -NotIn 'master', 'model', 'tempdb', 'msdb', 'resource'
        }
        $stepCounter = 0
        foreach ($db in $InputObject) {
            if ($stepCounter -eq 100) {
                $stepCounter = 0
            }
            if ($db.Name -in 'master', 'model', 'tempdb', 'msdb', 'resource') {
                Write-Message -Level Verbose "Encryption was not resumed for $($db.Name) on $($server.Name) because this database cannot be encrypted"
                continue
            }
            $server = $db.Parent
            # CHECK FOR SQL SERVER 2019!!!!!!!!
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Resumeing encryption for $($db.Name) on $($server.Name)" -TotalSteps $InputObject.Count
            try {
                # https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.databaseencryptionstate
                if (($db.DatabaseEncryptionKey.EncryptionState -in "EncryptionInProgress", "DecryptionInProgress", "EncryptionKeyChangesInProgress")) {
                    # This is not in SMO yet https://github.com/microsoft/sqlmanagementobjects/issues/77
                    $null = $db.Query("ALTER DATABASE [$($db.Name)] SET ENCRYPTION RESUME")
                    $null = $db.Refresh()
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name EncryptionState -value $db.DatabaseEncryptionKey.EncryptionState
                    Write-Message -Level Verbose "Encryption for $($db.Name) on $($server.Name) has been resumed"
                    $db | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, 'Name as DatabaseName', EncryptionEnabled, EncryptionState
                } else {
                    Write-Message -Level Verbose "Encryption for $($db.Name) on $($server.Name) is not in a state to be resumed"
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name EncryptionState -value $db.DatabaseEncryptionKey.EncryptionState
                    $db | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, 'Name as DatabaseName', EncryptionEnabled, EncryptionState
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }
        }
    }
}