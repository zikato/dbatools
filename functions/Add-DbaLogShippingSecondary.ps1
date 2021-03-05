function Add-DbaLogShippingSecondary {
    <#
.SYNOPSIS
    Adds a log shipping secondary to a database.

.DESCRIPTION
    Adds a log shipping secondary to a database.

    We sometimes need multiple seconaries in for a particular log shipped database.
    This command takes care of adding a secondary to the log shipping configuration.

.PARAMETER SqlInstance
    The target SQL Server instance or instances

.PARAMETER SqlCredential
    Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

    Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

    For MFA support, please use Connect-DbaInstance.

.PARAMETER Database
    The database or databases add the secondary to

.PARAMETER WhatIf
    Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
    Prompts you for confirmation before executing any changing operations within the command.

.PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
    Tags: LogShipping
    Author: Sander Stad (@sqlstad), sqlstad.nl

    Website: https://dbatools.io
    Copyright: (c) 2018 by dbatools, licensed under MIT
    License: MIT https://opensource.org/licenses/MIT

.LINK
    https://dbatools.io/Add-DbaLogShippingSecondary

.EXAMPLE

#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]

    param(
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Alias("SourceServerInstance", "SourceSqlServerSqlServer", "Source")]
        [DbaInstanceParameter]$SourceSqlInstance,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Alias("DestinationServerInstance", "DestinationSqlServer", "Destination")]
        [DbaInstanceParameter[]]$DestinationSqlInstance,
        [System.Management.Automation.PSCredential]
        $SourceSqlCredential,
        [System.Management.Automation.PSCredential]
        $DestinationSqlCredential,
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]]$Database,
        [string]$SecondaryDatabasePrefix,
        [string]$SecondaryDatabaseSuffix,
        [string]$CopyDestinationFolder,
        [string]$CopyJob,
        [string]$RestoreJob,
        [int]$RestoreDelay,
        [int]$RestoreThreshold,
        [string]$SharedPath,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        # Try connecting to the instance
        try {
            $SourceServer = Connect-SqlInstance -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Could not connect to Sql Server instance $SourceSqlInstance" -ErrorRecord $_ -Target $SourceSqlInstance
            return
        }

        $SourceServerName, $SourceInstanceName = $SourceSqlInstance.FullName.Split("\")

        # Check the database parameter
        if ($Database) {
            foreach ($db in $Database) {
                if ($db -notin $SourceServer.Databases.Name) {
                    Stop-Function -Message "Database $db cannot be found on instance $SourceSqlInstance" -Target $SourceSqlInstance
                }
            }

            $DatabaseCollection = $SourceServer.Databases | Where-Object { $_.Name -in $Database }

            $query = "SELECT * FROM msdb.dbo.log_shipping_primary_databases WHERE primary_database IN ($("'" + ($Database -join "','") + "'"))"

            $lsInfo = Invoke-DbaQuery -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential -Database msdb -Query $query
        } else {
            Stop-Function -Message "Please supply a database to set up log shipping for" -Target $SourceSqlInstance -Continue
        }

        # Checking parameters
        if (-not $RestoreDelay) {
            $RestoreDelay = 0
            Write-Message -Message "Restore delay set to $RestoreDelay" -Level Verbose
        }
        if (-not $RestoreThreshold) {
            $RestoreThreshold = 0
            Write-Message -Message "Restore Threshold set to $RestoreThreshold" -Level Verbose
        }
    }

    process {
        # Loop through each destination
        foreach ($destInstance in $DestinationSqlInstance) {

            # Try connecting to the instance
            try {
                $DestinationServer = Connect-SqlInstance -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Could not connect to Sql Server instance $destInstance" -ErrorRecord $_ -Target $destInstance
                return
            }

            # Check the copy destination
            if (-not $CopyDestinationFolder) {
                # Make a default copy destination by retrieving the backup folder and adding a directory
                $CopyDestinationFolder = "$($DestinationServer.Settings.BackupDirectory)\Logshipping"

                # Check to see if the path already exists
                Write-Message -Message "Testing copy destination path $CopyDestinationFolder" -Level Verbose
                if (Test-DbaPath -Path $CopyDestinationFolder -SqlInstance $destInstance -SqlCredential $DestinationCredential) {
                    Write-Message -Message "Copy destination $CopyDestinationFolder already exists" -Level Verbose
                } else {
                    # Check if force is being used
                    if (-not $Force) {
                        Stop-Function -Message "The copy destination '$CopyDestinationFolder' does not exist. Create the directory or use -Force to let it be created"
                    } # if not force
                    else {
                        # Try to create the copy destination on the local server
                        try {
                            Write-Message -Message "Creating copy destination folder $CopyDestinationFolder" -Level Verbose
                            New-Item $CopyDestinationFolder -ItemType Directory -Credential $DestinationCredential -Force:$Force | Out-Null
                            Write-Message -Message "Copy destination $CopyDestinationFolder created." -Level Verbose
                        } catch {
                            $setupResult = "Failed"
                            $comment = "Something went wrong creating the copy destination folder"
                            Stop-Function -Message "Something went wrong creating the copy destination folder $CopyDestinationFolder. `n$_" -Target $destInstance -ErrorRecord $_
                            return
                        }
                    } # else not force
                } # if test path copy destination
            } # if not copy destination

            # Loop through each of the databases
            foreach ($db in $DatabaseCollection) {

                $dbInfo = $lsInfo | Where-Object primary_database -eq $db.Name

                # Check the status of the database
                if ($db.RecoveryModel -ne 'Full') {
                    $setupResult = "Failed"
                    $comment = "Database $db is not in FULL recovery mode"

                    Stop-Function -Message  "Database $db is not in FULL recovery mode" -Target $SourceSqlInstance -Continue
                }

                # Set the intital destination database
                $SecondaryDatabase = $db.Name

                # Set the database prefix
                if ($SecondaryDatabasePrefix) {
                    $SecondaryDatabase = "$SecondaryDatabasePrefix$($db.Name)"
                }

                # Set the database suffix
                if ($SecondaryDatabaseSuffix) {
                    $SecondaryDatabase += $SecondaryDatabaseSuffix
                }

                # Set the copy destination folder to include the database name
                if ($CopyDestinationFolder.EndsWith("\")) {
                    $DatabaseCopyDestinationFolder = "$CopyDestinationFolder$($db.Name)"
                } else {
                    $DatabaseCopyDestinationFolder = "$CopyDestinationFolder\$($db.Name)"
                }
                Write-Message -Message "Copy destination folder set to $DatabaseCopyDestinationFolder." -Level Verbose

                # Check if the copy job name is set
                if ($CopyJob) {
                    $DatabaseCopyJob = "$($CopyJob)$($db.Name)"
                } else {
                    $DatabaseCopyJob = "LSCopy_$($SourceServerName)_$($db.Name)"
                }
                Write-Message -Message "Copy job name set to $DatabaseCopyJob" -Level Verbose

                # Check if the restore job name is set
                if ($RestoreJob) {
                    $DatabaseRestoreJob = "$($RestoreJob)$($db.Name)"
                } else {
                    $DatabaseRestoreJob = "LSRestore_$($SourceServerName)_$($db.Name)"
                }
                Write-Message -Message "Restore job name set to $DatabaseRestoreJob" -Level Verbose

                # Setting the backup network path for the database
                $DatabaseSharedPath = $dbInfo.backup_share
                Write-Message -Message "Backup network path set to $DatabaseSharedPath." -Level Verbose

                if ($PSCmdlet.ShouldProcess("Configuring logshipping from primary to secondary database")) {
                    Write-Message -Message "Configuring logshipping from primary to secondary database." -Level Verbose
                    try {
                        $lsParams = @{
                            SqlInstance            = $SourceSqlInstance
                            SqlCredential          = $SourceSqlCredential
                            PrimaryDatabase        = $($db.Name)
                            SecondaryDatabase      = $SecondaryDatabase
                            SecondaryServer        = $destInstance
                            SecondarySqlCredential = $DestinationSqlCredential
                        }

                        #New-DbaLogShippingPrimarySecondary @lsParams

                    } catch {
                        $setupResult = "Failed"
                        $comment = "Something went wrong setting up log shipping for secondary instance"
                    }
                }

                if ($PSCmdlet.ShouldProcess("Configuring logshipping from secondary database $SecondaryDatabase to primary database $db.")) {
                    try {
                        Write-Message -Message "Configuring logshipping from secondary database $SecondaryDatabase to primary database $db." -Level Verbose

                        $lsParams = @{
                            SqlInstance                = $destInstance
                            SqlCredential              = $DestinationSqlCredential
                            BackupSourceDirectory      = $DatabaseSharedPath
                            BackupDestinationDirectory = $DatabaseCopyDestinationFolder
                            CopyJob                    = $DatabaseCopyJob
                            FileRetentionPeriod        = $dbInfo.backup_retention_period
                            MonitorServer              = $dbInfo.monitor_server
                            MonitorServerSecurityMode  = $dbInfo.monitor_server_security_mode
                            MonitorCredential          = $SecondaryMonitorCredential
                            PrimaryServer              = $SourceSqlInstance
                            PrimaryDatabase            = $($db.Name)
                            RestoreJob                 = $DatabaseRestoreJob
                            Force                      = $Force
                        }

                        #New-DbaLogShippingSecondaryPrimary @lsParams
                    } catch {
                        $setupResult = "Failed"
                        $comment = "Something went wrong setting up log shipping for secondary instance"
                    }
                }

                if ($PSCmdlet.ShouldProcess("Configuring logshipping for secondary database")) {
                    try {
                        Write-Message -Message "Configuring logshipping for secondary database." -Level Verbose

                        $lsParams = @{
                            SqlInstance               = $destInstance
                            SqlCredential             = $DestinationSqlCredential
                            SecondaryDatabase         = $SecondaryDatabase
                            PrimaryServer             = $SourceSqlInstance
                            PrimaryDatabase           = $($db.Name)
                            RestoreDelay              = $RestoreDelay
                            RestoreMode               = $DatabaseStatus
                            DisconnectUsers           = $DisconnectUsers
                            RestoreThreshold          = $RestoreThreshold
                            ThresholdAlertEnabled     = $SecondaryThresholdAlertEnabled
                            HistoryRetention          = $HistoryRetention
                            MonitorServer             = $dbInfo.monitor_server
                            MonitorServerSecurityMode = $dbInfo.monitor_server_security_mode
                            MonitorCredential         = $SecondaryMonitorCredential
                        }
                        ""
                        $lsParams
                        #New-DbaLogShippingSecondaryDatabase @lsParams
                    } catch {
                        $setupResult = "Failed"
                        $comment = "Something went wrong setting up log shipping for secondary instance"
                    }
                }

            } # End for each database
        } # End for each destination instance
    } # End process
}