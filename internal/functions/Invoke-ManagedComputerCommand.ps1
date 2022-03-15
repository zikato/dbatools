function Invoke-ManagedComputerCommand {
    <#
        .SYNOPSIS
            Runs wmi commands against a target system.

        .DESCRIPTION
            Runs wmi commands against a target system.
            Either directly or over PowerShell remoting.

        .PARAMETER ComputerName
            The target to run against. Must be resolvable.

        .PARAMETER Credential
            Credentials to use when using PowerShell remoting.

        .PARAMETER ScriptBlock
            The scriptblock to execute.
            Use $wmi to access the smo wmi object.
            Must not include a param block!

        .PARAMETER ArgumentList
            The arguments to pass to your scriptblock.
            Access them within the scriptblock using the automatic variable $args

        .PARAMETER EnableException
            Left in for legacy reasons. This command will throw no matter what
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Alias("Server")]
        [dbainstanceparameter]$ComputerName,
        [PSCredential]$Credential,
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList,
        [switch]$EnableException # Left in for legacy but this command needs to throw
    )

    if (Get-DbatoolsConfigValue -FullName 'ComputerManagement.Type.Disable.WMI') {
        Write-Message -Level Verbose -Message "We don't use direct WMI but PowerShell remoting"
        $resolvedComputerName = Resolve-DbaComputerName -ComputerName $ComputerName -Credential $Credential
        $null = Test-ElevationRequirement -ComputerName $resolvedComputerName -EnableException $true
        $ArgumentList += '127.0.0.1'
        $result = Invoke-Command2 -ComputerName $resolvedComputerName -ScriptBlock $scriptBlock -ArgumentList $ArgumentList -Credential $Credential -ErrorAction Stop
        if ($result.Exception) {
            # The new code pattern for WMI calls like in Set-DbaNetworkConfiguration is used where all exceptions are catched and return as part of an object.
            foreach ($msg in $result.Verbose) {
                Write-Message -Level Verbose -Message $msg
            }
            Write-Message -Level Verbose -Message "Execution against $computer failed with: $($result.Exception)"
            Stop-Function -Message "Failed." -Target $computer -ErrorRecord $result.Exception
        } else {
            # The old code pattern is used or no exception was catched, so just return the result
            $result
        }
    } else {
        Write-Message -Level Verbose -Message "We use direct WMI"
        $resolvedComputer = Resolve-DbaNetworkName -ComputerName $ComputerName -Credential $Credential
        $null = Test-ElevationRequirement -ComputerName $resolvedComputerName -EnableException $true
        $ArgumentList += $resolvedComputer.IpAddress
        try {
            $result = Invoke-Command2 -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
            if ($result.Exception) {
                # The new code pattern for WMI calls like in Set-DbaNetworkConfiguration is used where all exceptions are catched and return as part of an object.
                foreach ($msg in $result.Verbose) {
                    Write-Message -Level Verbose -Message $msg
                }
                Write-Message -Level Verbose -Message "Execution against $($resolvedComputer.IpAddress) failed with: $($result.Exception)"
                Stop-Function -Message "Failed." -Target $computer -ErrorRecord $result.Exception -EnableException $true
            } else {
                # The old code pattern is used or no exception was catched, so just return the result
                $result
            }
        } catch {
            Write-Message -Level Verbose -Message "Local connection attempt to $computer failed. Connecting remotely."
            Invoke-Command2 -ComputerName $resolvedComputer.FullComputerName -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -Credential $Credential -ErrorAction Stop
        }
    }
}