<#
    .SYNOPSIS

    Discovery script for finding all SQL Logins on a the target machine

    .DESCRIPTION

    Find the SQL Logins on all instances found on a the target machine.

    .NOTES

    Depends upon dbatools module being installed on the Secret Server Web Node or the Distributed Engine
    Reference: https://www.powershellgallery.com/packages/dbatools/
    Tested with version 1.0.107

    logPath variable below used for troubleshooting if required, file is written to this path with errors.
    A file for each server will be created, and overwritten on each run.
#>
$logPath = 'C:\scripts'
$params = $args

$TargetServer = $params[0]
$Username = "$($params[1])\$($params[2])"
$Password = $params[3]

if ( $Username -and $Password ) {
    $passwd = $Password | ConvertTo-SecureString -AsPlainText -Force
    $sqlCred = New-Object System.Management.Automation.PSCredential -ArgumentList $Username,$passwd
}

$ProgressPreference = 'SilentlyContinue'
if (-not (Get-InstalledModule dbatools)) {
    throw "The module dbatools is required for this script. Please run 'Install-Module dbatools' in an elevated session on your Distributed Engine and/or Web Node."
} else {
    Import-Module dbatools -Force
    <#
        disable dbatools commands attempting to resolve the target name
    #>
    $null = Set-DbatoolsConfig -FullName commands.resolve-dbanetworkname.bypass -Value $true
}

<#
    Find all the SQL Server instances
#>
try {
    <#
        Create a second credential and uncomment for the privileged account used to scan the server for SQL Server installations
        By default the Discovery account will be used
    #>
    $p = @{
        ComputerName    = $TargetServer
        # Credential = $cred
        ScanType        = 'SqlService'
        EnableException = $true
    }
    $sqlEngines = Find-DbaInstance @p
} catch {
    throw "No SQL Server services found on $TargetServer"
}

if ($sqlEngines) {
    foreach ($engine in $sqlEngines) {
        $sqlInstanceValue = $engine.SqlInstance
        try {
            <#
                Connect to each instance found
            #>
            $p = @{
                SqlInstance   = $sqlInstanceValue
                SqlCredential = $sqlCred
                ErrorAction   = 'Stop'
            }
            try {
                $cn = Connect-DbaInstance @p
            } catch {
                if (Test-Path $logPath) {
                    Write-Output "[$(Get-Date -Format yyyyMMdd)] Issue connecting to $sqlInstanceValue - $($_.Exception.Message)" | Out-File "$logPath\$($TargetServer)_findsqllogins.txt" -Force
                } else {
                    Write-Output "[$(Get-Date -Format yyyyMMdd)] Issue connecting to $sqlInstanceValue - $($_.Exception.Message)"
                }
                continue
            }

            <#
                Find the logins on the instance
            #>
            $p = @{
                SqlInstance     = $cn
                Type            = 'SQL'
                ExcludeFilter   = '##*'
                EnableException = $true
            }
            $logins = Get-DbaLogin @p
        } catch {
            if (Test-Path $logPath) {
                if (Test-Path "$logPath\$($TargetServer)_findsqllogins.txt") { $append = $true}
                Write-Output "[$(Get-Date -Format yyyyMMdd)] Issue connecting to $sqlInstanceValue - $($_.Exception.Message)" | Out-File "$logPath\$($TargetServer)_findsqllogins.txt" -Append:$append
            } else {
                Write-Output "[$(Get-Date -Format yyyyMMdd)] Issue connecting to $sqlInstanceValue - $($_.Exception.Message)"
            }
            continue
        }

        <#
            Output object for Discovery
        #>
        foreach ($login in $logins) {
            [PSCustomObject]@{
                Machine  = $login.Parent.Name
                Username = $login.Name
            }
        }
    }
}