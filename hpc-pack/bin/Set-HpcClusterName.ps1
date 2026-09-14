<#
.Synopsis
    Specifies the HPC cluster to which the current computer will connect.

.DESCRIPTION
    This script sets the connection string of the HPC cluster to which the current computer (HPC cluster node) will connect.

.NOTES
    This cmdlet requires that the current computer is a compute node, broker node, or workstation node in an HPC Pack cluster.

.EXAMPLE
    PS > Set-HpcClusterName.ps1 -ConnectionString NewHN
    Sets the HPC cluster connection string for the current computer as NewHN

.EXAMPLE
    PS > Set-HpcClusterName.ps1 -ConnectionString NewHN1,NewHN2,NewHN3 -Delay 10
    Sets the HPC cluster connection string for the current computer as 'NewHN1,NewHN2,NewHN3' after 10 seconds

.EXAMPLE
    PS > Set-HpcClusterName.ps1 -ConnectionString NewHN -RunAsScheduledTask
    Schedules a task to set the HPC cluster connection string for the current computer as NewHN
#>
Param
(
    # The connection string of the HPC cluster that you want the current computer connected to.
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [String[]] $ConnectionString,

    # If specified, the delay time in seconds for the operation.
    [Parameter(Mandatory=$false)]
    [ValidateRange(0, 3600)]
    [int] $Delay = 0,

    # If specified, sets the HPC cluster connection string using a scheduled task.
    [Parameter(Mandatory=$false)]
    [Switch] $RunAsScheduledTask
)

$VerbosePreference = "Continue"
$datestr = Get-Date -Format "yyyy_MM_dd-HH_mm_ss"
$Script:LogFile = "$env:temp\Set-HpcClusterName-$datestr.log"
$ClusterConnectionString = $ConnectionString -join ','

function WriteLog
{
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String] $Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet("Error","Warning","Verbose")]
        [String] $LogLevel = "Verbose"
    )
    
    $timestr = Get-Date -Format 'MM/dd/yyyy HH:mm:ss'
    $NewMessage = "$timestr - $Message"
    switch($LogLevel)
    {
        "Error"     {Write-Error   $NewMessage; break}
        "Warning"   {Write-Warning $NewMessage; break}
        "Verbose"   {Write-Verbose $NewMessage; break}
    }
       
    try
    {
        $NewMessage = "[$LogLevel]$timestr - $Message"
        Add-Content $Script:LogFile $NewMessage -ErrorAction SilentlyContinue
    }
    catch
    {
        #Ignore the error
    }
}

try
{
    $HPCKeyPath = "HKLM:\SOFTWARE\Microsoft\HPC"
    $HPCWow6432KeyPath = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\HPC"
    $clusNameItem = $null
    $roleItem = $null
    $keyExists = Test-Path -Path $HPCKeyPath
    if($keyExists)
    {
        $clusNameItem = Get-ItemProperty -Name ClusterConnectionString -LiteralPath $HPCKeyPath -ErrorAction SilentlyContinue
        $roleItem = Get-ItemProperty -Name InstalledRole -LiteralPath $HPCKeyPath -ErrorAction SilentlyContinue
    }

    if((-not $keyExists) -or ($clusNameItem -eq $null) -or ($roleItem -eq $null))
    {
        throw "$env:ComputerName is not a valid HPC cluster node"
    }

    if($roleItem.InstalledRole -contains "HN")
    {
        throw "$env:ComputerName cannot be moved to the cluster '$ClusterConnectionString' because it is a head node"
    }

    if($clusNameItem.ClusterConnectionString -eq $ClusterConnectionString)
    {
        WriteLog "$env:ComputerName already belongs to HPC cluster $ClusterConnectionString" -LogLevel Warning
        return
    }

    if($RunAsScheduledTask.IsPresent)
    {
        # Schedule a task to run this script itself, start the scheduled task immediately and return.
        $selfFullPath = $MyInvocation.MyCommand.Definition
        WriteLog "The full path of this script is $selfFullPath" -LogLevel Verbose
        # Because ScheduledTasks PowerShell module not available in Windows Server 2008 R2,
        # We use ComObject Schedule.Service to schedule task
        WriteLog "Scheduling task to set HPC cluster connection string to '$ClusterConnectionString' with a delay of $Delay seconds" -LogLevel Verbose
        $randNum = Get-Random -Maximum 100 -Minimum 1
        $taskName = "SetHpcCluster_$randNum"
        $schdService = new-object -ComObject "Schedule.Service"
        $schdService.Connect("localhost")
        $rootFolder = $schdService.GetFolder("\")
        $taskDefinition = $schdService.NewTask(0)
        $setAction = $taskDefinition.Actions.Create(0)
        $setAction.Path = "PowerShell.exe"
        $setClusNameCmd = ". '$selfFullPath' -ConnectionString $ClusterConnectionString -Delay $Delay"
        $setAction.Arguments = '-ExecutionPolicy ByPass -Command "{0}"' -f $setClusNameCmd
        $removeAction = $taskDefinition.Actions.Create(0)
        $removeAction.Path = "SchTasks.exe"
        $removeAction.Arguments = "/Delete /TN $taskName /F"
        $setClusterTask = $Rootfolder.RegisterTaskDefinition($taskName, $taskDefinition, 2, "system", $null, 5)
        try
        {
            $setClusterTask.Run($null) | Out-Null
        }
        catch
        {
            $Rootfolder.DeleteTask($taskName, 0) | Out-Null
            throw
        }
        WriteLog "The task starts to run to set the HPC cluster connection string" -LogLevel Verbose
        return
    }

    if($Delay -gt 0)
    {
        WriteLog "HPC cluster connection string will be updated after $Delay seconds" -LogLevel Verbose
        Start-Sleep -Seconds $Delay
    }

    WriteLog "The current Cluster connection string: $($clusNameItem.ClusterConnectionString)" -LogLevel Verbose
    WriteLog "The current Installed HPC Role(s): $($roleItem.InstalledRole)" -LogLevel Verbose

    # Check the HPC Version by the production version of HpcNodeManager.exe
    $HpcNodeManagerExePath = [System.IO.Path]::Combine($env:CCP_HOME, "Bin\HpcNodeManager.exe")
    if(-not (Test-Path -Path $HpcNodeManagerExePath -PathType Leaf))
    {
        throw "$env:ComputerName is not a valid HPC cluster node: $HpcNodeManagerExePath not found"
    }

    $hpcVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($HpcNodeManagerExePath).ProductVersion
    WriteLog "The current HPC production version is $hpcVersion" -LogLevel Verbose
    $BNServiceList = @("HpcBroker")
    if($hpcVersion -ge "4.0")
    {
        $CNServiceList = @("HpcManagement", "HpcNodeManager", "msmpi", "HpcMonitoringClient", "HpcSoaDiagMon")
        $WNServiceList = @("HpcManagement", "HpcNodeManager", "msmpi", "HpcMonitoringClient")
    }
    else
    {
        $CNServiceList = $WNServiceList = @("HpcManagement", "HpcNodeManager", "msmpi")
    }

    $hpcServices = @()
    if($roleItem.InstalledRole -contains "BN")
    {
        $hpcServices += $BNServiceList
    }
    if($roleItem.InstalledRole -contains "CN")
    {
        $hpcServices += $CNServiceList
    }
    if($roleItem.InstalledRole -contains "WN")
    {
        $hpcServices += $WNServiceList
    }

    $hpcServices = $hpcServices | Select -Unique
    if($hpcServices.Count -eq 0)
    {
        throw "$env:ComputerName is not a valid HPC cluster node"
    }

    # Check the existence of the HPC Services and stop them
    foreach($svcname in $hpcServices)
    {
        $service = Get-Service -Name $svcname -ErrorAction SilentlyContinue
        if($service -eq $null)
        {
            throw "The service $svcname doesn't exist"
        }
        else
        {
            WriteLog "Stopping service: $svcname" -LogLevel Verbose
            Stop-Service -Name $svcname -Force
        }
    }

    WriteLog "Updating HPC cluster connection string in Registry Table on $env:ComputerName" -LogLevel Verbose
    Set-ItemProperty -Path $HPCKeyPath -Name ClusterConnectionString -Value $ClusterConnectionString
    if(Test-Path $HPCWow6432KeyPath)
    {
        Set-ItemProperty -Path $HPCWow6432KeyPath -Name ClusterConnectionString -Value $ClusterConnectionString
    }

    WriteLog "Updating environment variable 'CCP_SCHEDULER' on $env:ComputerName" -LogLevel Verbose
    [Environment]::SetEnvironmentVariable("CCP_SCHEDULER", $ClusterConnectionString, [System.EnvironmentVariableTarget]::Machine)

    WriteLog "Updating environment variable 'CCP_CONNECTIONSTRING' on $env:ComputerName" -LogLevel Verbose
    [Environment]::SetEnvironmentVariable("CCP_CONNECTIONSTRING", $ClusterConnectionString, [System.EnvironmentVariableTarget]::Machine)

    # Set the Startup Type of HPC Services to 'Automatic' in case some of them are not 'Automatic'
    $hpcServices | Set-Service -StartupType Automatic
    $startFailure = $false
    foreach($svcname in $hpcServices)
    {
        Start-Service -Name $svcname
        if(-not $?)
        {
            $startFailure = $true
            WriteLog ("Failed to start service: $svcname : " + $Error[0]) -LogLevel Warning
        }
    }

    if(-not $startFailure)
    {
        WriteLog "Successfully updated HPC cluster connection string to $ClusterConnectionString" -LogLevel Verbose
    }
    else
    {
        # if failed to restart service, restart the computer as a workaround
        Restart-Computer -Force -Delay 20
    }
}
catch
{
    WriteLog "Failed to update HPC cluster connection string to $ClusterConnectionString : $_" -LogLevel Error
    throw
}

# SIG # Begin signature block
# MIIdhwYJKoZIhvcNAQcCoIIdeDCCHXQCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUdNmgjOrrAdlrUC9SiIgfatFY
# /v6gghhjMIIE3jCCA8agAwIBAgITMwAAAVMi29XcAx7KbwAAAAABUzANBgkqhkiG
# 9w0BAQUFADB3MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEw
# HwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EwHhcNMTkxMjE5MDExMjU5
# WhcNMjEwMzE3MDExMjU5WjCBzjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEpMCcGA1UECxMgTWljcm9zb2Z0IE9wZXJhdGlvbnMgUHVlcnRvIFJp
# Y28xJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOkY3QTYtRTI1MS0xNTBBMSUwIwYD
# VQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIIBIjANBgkqhkiG9w0B
# AQEFAAOCAQ8AMIIBCgKCAQEAq1diK9JlonJ+oylzVWABNR+Ch+1DFBtELj+s2Clp
# mny7jKTaKBtfJj/VXgmPb0clmTSW/ORG4E7U6a+byrPi+2TRm+KPnOUhpjEWkrwU
# s7p9Yri6MkYVIpH6u7hDFpftVw0cnqD75GriLHPxAL9gXnWCijYmWrAwbQmiFCnv
# KLNd57OoyHOKnbNoE/ZY3nfXXiMblVCfiEeAk3c/FhEC1ZgePKWzPv3cDf77Clka
# DtGGkL1PLQOWKGlED6WBlKQWwwBbrRCcKn/DFhQjBVL7hKBvKIx41Onu1q4ZR3V3
# P4cKvhpgVtBzgrWyV49NW6zpbhTiNB8Hv0KJBmRSYpo5wQIDAQABo4IBCTCCAQUw
# HQYDVR0OBBYEFKYM4eA/3NrcTBY4Uo+HjtARq+DTMB8GA1UdIwQYMBaAFCM0+NlS
# RnAK7UD7dvuzK7DDNbMPMFQGA1UdHwRNMEswSaBHoEWGQ2h0dHA6Ly9jcmwubWlj
# cm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY3Jvc29mdFRpbWVTdGFtcFBD
# QS5jcmwwWAYIKwYBBQUHAQEETDBKMEgGCCsGAQUFBzAChjxodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY3Jvc29mdFRpbWVTdGFtcFBDQS5jcnQw
# EwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcNAQEFBQADggEBAEPT3fFVLrkO
# s336Dh2XtV7NzB1XvFiBhTeDEWCAKb67K1Et2Qudz8wk37hfWgX0DIYi0lvDrZxf
# iLedK9xl/+CGKC8Cnle0c4kQxHzsJMh9TrYzfMkxzXQpyMAXm8gyzInlM1khJobC
# olWP97sqZdcESpLo5mWVz6uuVys59KaVND4VictBo1mH+UpZ4PVyTgpUgB0M5egL
# I7PWSAwfPVwadiKaREjVpd02X3mQWcCyeFrFLcj5zL6bOWArxBWVAQ+okjDr6utc
# 9bdm3DodUkNCauvvpVQhR+WZ9E6KoIfsgLrFfW1WhtMmF1msCk0bOdsMAwjD2gXM
# uuGf3UmLPt0wggX0MIID3KADAgECAhMzAAABhk0hdaDZB74sAAAAAAGGMA0GCSqG
# SIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# KDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTEwHhcNMjAw
# MzA0MTgzOTQ2WhcNMjEwMzAzMTgzOTQ2WjB0MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNyb3NvZnQgQ29ycG9yYXRpb24w
# ggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC49eyyaaieg3Xb7ew+/hA3
# 4gqzRuReb9svBF6N3+iLD5A0iMddtunnmbFVQ+lNWphf/xOGef5vXMMMk744txo/
# kT6CKq0GzV+IhAqDytjH3UgGhLBNZ/UWuQPgrnhwafQ3ZclsXo1lto4pyps4+X3R
# yQfnxCwqtjRxjCQ+AwIzk0vSVFnId6AwbB73w2lJ+MC+E6nVmyvikp7DT2swTF05
# JkfMUtzDosktz/pvvMWY1IUOZ71XqWUXcwfzWDJ+96WxBH6LpDQ1fCQ3POA3jCBu
# 3mMiB1kSsMihH+eq1EzD0Es7iIT1MlKERPQmC+xlK+9pPAw6j+rP2guYfKrMFr39
# AgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBgorBgEEAYI3TAgBBggrBgEFBQcDAzAd
# BgNVHQ4EFgQUhTFTFHuCaUCdTgZXja/OAQ9xOm4wRQYDVR0RBD4wPKQ6MDgxHjAc
# BgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEWMBQGA1UEBRMNMjMwMDEyKzQ1
# ODM4NDAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzcitW2oynUClTBUBgNVHR8ETTBL
# MEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWND
# b2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEGCCsGAQUFBwEBBFUwUzBRBggr
# BgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9N
# aWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0MAwGA1UdEwEB/wQCMAAwDQYJ
# KoZIhvcNAQELBQADggIBAEDkLXWKDtJ8rLh3d7XP1xU1s6Gt0jDqeHoIpTvnsREt
# 9MsKriVGKdVVGSJow1Lz9+9bINmPZo7ZdMhNhWGQQnEF7z/3czh0MLO0z48cxCrj
# Lch0P2sxvtcaT57LBmEy+tbhlUB6iz72KWavxuhP5zxKEChtLp8gHkp5/1YTPlvR
# YFrZr/iup2jzc/Oo5N4/q+yhOsRT3KJu62ekQUUPsPU2bWsaF/hUPW/L2O1Fecf+
# 6OOJLT2bHaAzr+EBAn0KAUiwdM+AUvasG9kHLX+IXXlEZvfsXGzzxFlWzNbpM99u
# mWWMQPTGZPpSCTDDs/1Ci0Br2/oXcgayYLaZCWsj1m/a0V8OHZGbppP1RrBeLQKf
# ATjtAl0xrhMr4kgfvJ6ntChg9dxy4DiGWnsj//QywUs1UxVchRR7eFaP3M8/BV0e
# eMotXwTNIwzSd3uAzAI+NSrN5pVlQeC0XXTueeDuxDch3S5UUdDOvdlOdlRAa+85
# Si6HmEUgx3j0YYSC1RWBdEhwsAdH6nXtXEshAAxf8PWh2wCsczMe/F4vTg4cmDsB
# TZwwrHqL5krX++s61sLWA67Yn4Db6rXV9Imcf5UMCq09wJj5H93KH9qc1yCiJzDC
# tbtgyHYXAkSHQNpoj7tDX6ko9gE8vXqZIGj82mwDTAY9ofRH0RSMLJqpgLrBPCKN
# MIIGBzCCA++gAwIBAgIKYRZoNAAAAAAAHDANBgkqhkiG9w0BAQUFADBfMRMwEQYK
# CZImiZPyLGQBGRYDY29tMRkwFwYKCZImiZPyLGQBGRYJbWljcm9zb2Z0MS0wKwYD
# VQQDEyRNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkwHhcNMDcw
# NDAzMTI1MzA5WhcNMjEwNDAzMTMwMzA5WjB3MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSEwHwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCfoWyx39tIkip8ay4Z
# 4b3i48WZUSNQrc7dGE4kD+7Rp9FMrXQwIBHrB9VUlRVJlBtCkq6YXDAm2gBr6Hu9
# 7IkHD/cOBJjwicwfyzMkh53y9GccLPx754gd6udOo6HBI1PKjfpFzwnQXq/QsEIE
# ovmmbJNn1yjcRlOwhtDlKEYuJ6yGT1VSDOQDLPtqkJAwbofzWTCd+n7Wl7PoIZd+
# +NIT8wi3U21StEWQn0gASkdmEScpZqiX5NMGgUqi+YSnEUcUCYKfhO1VeP4Bmh1Q
# CIUAEDBG7bfeI0a7xC1Un68eeEExd8yb3zuDk6FhArUdDbH895uyAc4iS1T/+QXD
# wiALAgMBAAGjggGrMIIBpzAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBQjNPjZ
# UkZwCu1A+3b7syuwwzWzDzALBgNVHQ8EBAMCAYYwEAYJKwYBBAGCNxUBBAMCAQAw
# gZgGA1UdIwSBkDCBjYAUDqyCYEBWJ5flJRP8KuEKU5VZ5KShY6RhMF8xEzARBgoJ
# kiaJk/IsZAEZFgNjb20xGTAXBgoJkiaJk/IsZAEZFgltaWNyb3NvZnQxLTArBgNV
# BAMTJE1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eYIQea0WoUqg
# pa1Mc1j0BxMuZTBQBgNVHR8ESTBHMEWgQ6BBhj9odHRwOi8vY3JsLm1pY3Jvc29m
# dC5jb20vcGtpL2NybC9wcm9kdWN0cy9taWNyb3NvZnRyb290Y2VydC5jcmwwVAYI
# KwYBBQUHAQEESDBGMEQGCCsGAQUFBzAChjhodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpL2NlcnRzL01pY3Jvc29mdFJvb3RDZXJ0LmNydDATBgNVHSUEDDAKBggr
# BgEFBQcDCDANBgkqhkiG9w0BAQUFAAOCAgEAEJeKw1wDRDbd6bStd9vOeVFNAbEu
# dHFbbQwTq86+e4+4LtQSooxtYrhXAstOIBNQmd16QOJXu69YmhzhHQGGrLt48ovQ
# 7DsB7uK+jwoFyI1I4vBTFd1Pq5Lk541q1YDB5pTyBi+FA+mRKiQicPv2/OR4mS4N
# 9wficLwYTp2OawpylbihOZxnLcVRDupiXD8WmIsgP+IHGjL5zDFKdjE9K3ILyOpw
# Pf+FChPfwgphjvDXuBfrTot/xTUrXqO/67x9C0J71FNyIe4wyrt4ZVxbARcKFA7S
# 2hSY9Ty5ZlizLS/n+YWGzFFW6J1wlGysOUzU9nm/qhh6YinvopspNAZ3GmLJPR5t
# H4LwC8csu89Ds+X57H2146SodDW4TsVxIxImdgs8UoxxWkZDFLyzs7BNZ8ifQv+A
# eSGAnhUwZuhCEl4ayJ4iIdBD6Svpu/RIzCzU2DKATCYqSCRfWupW76bemZ3KOm+9
# gSd0BhHudiG/m4LBJ1S2sWo9iaF2YbRuoROmv6pH8BJv/YoybLL+31HIjCPJZr2d
# HYcSZAI9La9Zj7jkIeW1sMpjtHhUBdRBLlCslLCleKuzoJZ1GtmShxN1Ii8yqAhu
# oFuMJb+g74TKIdbrHk/Jmu5J4PcBZW+JC33Iacjmbuqnl84xKf8OxVtc2E0bodj6
# L54/LlUWa8kTo/0wggd6MIIFYqADAgECAgphDpDSAAAAAAADMA0GCSqGSIb3DQEB
# CwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYD
# VQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAxMTAe
# Fw0xMTA3MDgyMDU5MDlaFw0yNjA3MDgyMTA5MDlaMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCr
# 8PpyEBwurdhuqoIQTTS68rZYIZ9CGypr6VpQqrgGOBoESbp/wwwe3TdrxhLYC/A4
# wpkGsMg51QEUMULTiQ15ZId+lGAkbK+eSZzpaF7S35tTsgosw6/ZqSuuegmv15ZZ
# ymAaBelmdugyUiYSL+erCFDPs0S3XdjELgN1q2jzy23zOlyhFvRGuuA4ZKxuZDV4
# pqBjDy3TQJP4494HDdVceaVJKecNvqATd76UPe/74ytaEB9NViiienLgEjq3SV7Y
# 7e1DkYPZe7J7hhvZPrGMXeiJT4Qa8qEvWeSQOy2uM1jFtz7+MtOzAz2xsq+SOH7S
# nYAs9U5WkSE1JcM5bmR/U7qcD60ZI4TL9LoDho33X/DQUr+MlIe8wCF0JV8YKLbM
# Jyg4JZg5SjbPfLGSrhwjp6lm7GEfauEoSZ1fiOIlXdMhSz5SxLVXPyQD8NF6Wy/V
# I+NwXQ9RRnez+ADhvKwCgl/bwBWzvRvUVUvnOaEP6SNJvBi4RHxF5MHDcnrgcuck
# 379GmcXvwhxX24ON7E1JMKerjt/sW5+v/N2wZuLBl4F77dbtS+dJKacTKKanfWeA
# 5opieF+yL4TXV5xcv3coKPHtbcMojyyPQDdPweGFRInECUzF1KVDL3SV9274eCBY
# LBNdYJWaPk8zhNqwiBfenk70lrC8RqBsmNLg1oiMCwIDAQABo4IB7TCCAekwEAYJ
# KwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFEhuZOVQBdOCqhc3NyK1bajKdQKVMBkG
# CSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8E
# BTADAQH/MB8GA1UdIwQYMBaAFHItOgIxkEO5FAVO4eqnxzHRI4k0MFoGA1UdHwRT
# MFEwT6BNoEuGSWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1
# Y3RzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18yMi5jcmwwXgYIKwYBBQUHAQEE
# UjBQME4GCCsGAQUFBzAChkJodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2Nl
# cnRzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18yMi5jcnQwgZ8GA1UdIASBlzCB
# lDCBkQYJKwYBBAGCNy4DMIGDMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpb3BzL2RvY3MvcHJpbWFyeWNwcy5odG0wQAYIKwYBBQUHAgIw
# NB4yIB0ATABlAGcAYQBsAF8AcABvAGwAaQBjAHkAXwBzAHQAYQB0AGUAbQBlAG4A
# dAAuIB0wDQYJKoZIhvcNAQELBQADggIBAGfyhqWY4FR5Gi7T2HRnIpsLlhHhY5KZ
# QpZ90nkMkMFlXy4sPvjDctFtg/6+P+gKyju/R6mj82nbY78iNaWXXWWEkH2LRlBV
# 2AySfNIaSxzzPEKLUtCw/WvjPgcuKZvmPRul1LUdd5Q54ulkyUQ9eHoj8xN9ppB0
# g430yyYCRirCihC7pKkFDJvtaPpoLpWgKj8qa1hJYx8JaW5amJbkg/TAj/NGK978
# O9C9Ne9uJa7lryft0N3zDq+ZKJeYTQ49C/IIidYfwzIY4vDFLc5bnrRJOQrGCsLG
# ra7lstnbFYhRRVg4MnEnGn+x9Cf43iw6IGmYslmJaG5vp7d0w0AFBqYBKig+gj8T
# TWYLwLNN9eGPfxxvFX1Fp3blQCplo8NdUmKGwx1jNpeG39rz+PIWoZon4c2ll9Du
# XWNB41sHnIc+BncG0QaxdR8UvmFhtfDcxhsEvt9Bxw4o7t5lL+yX9qFcltgA1qFG
# vVnzl6UJS0gQmYAf0AApxbGbpT9Fdx41xtKiop96eiL6SJUfq/tHI4D1nvi/a7dL
# l+LrdXga7Oo3mXkYS//WsyNodeav+vyL6wuA6mk7r/ww7QRMjt/fdW1jkT3RnVZO
# T7+AVyKheBEyIXrvQQqxP/uozKRdwaGIm1dxVk5IRcBCyZt2WwqASGv9eZ/BvW1t
# aslScxMNelDNMYIEjjCCBIoCAQEwgZUwfjELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQ
# Q0EgMjAxMQITMwAAAYZNIXWg2Qe+LAAAAAABhjAJBgUrDgMCGgUAoIGiMBkGCSqG
# SIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3
# AgEVMCMGCSqGSIb3DQEJBDEWBBSRBOw44v2lL2yQqSlAsNTtGX/RODBCBgorBgEE
# AYI3AgEMMTQwMqAUgBIATQBpAGMAcgBvAHMAbwBmAHShGoAYaHR0cDovL3d3dy5t
# aWNyb3NvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBAA56FjFMvpCP/xRaL9VGdIEb
# AKMAd11+TQZEAg0mLtw0D+u0NORcd5tx4io+KtRLT9C7g/Q6fI1gCPME3oTbNlqk
# R/LXMz+B90OrkFoM61te1jZHGp1kpQJsQNsTyQ3RJ3Crc+khMh5JV2MigwtEahk8
# DZm5eHpqzoeyHOYKU5HPEC6fym3se+ZpmgSIjGcTA1yQBBc0IwxBnBuIY1G+2PNI
# rRTeyjMzeFMQQNIEq3oRLXpxqYL1l6l2hj/SXDHDBlm676XbxrI2xzmBT6NpRXQ4
# BxNgKsoD/QHJRBWVCSfxMyUgZ+s1fZDFfyJYsG89vP24mrI3OWpw4SpEFd+U5cqh
# ggIoMIICJAYJKoZIhvcNAQkGMYICFTCCAhECAQEwgY4wdzELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEhMB8GA1UEAxMYTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgUENBAhMzAAABUyLb1dwDHspvAAAAAAFTMAkGBSsOAwIaBQCgXTAYBgkq
# hkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yMDA2MDcxMjM2
# MzNaMCMGCSqGSIb3DQEJBDEWBBThYf5ASygFl4inCUP8yN83fLqRVDANBgkqhkiG
# 9w0BAQUFAASCAQAvPgqnqfk0g870oB+BgSS5b+5yqprxKZnS0fIJTWh+XdUVkST6
# lITjzqBb1Ph+4u3zbDVktk5Mg4vLPrIq9d40i6JkvMWem62q5htNN59Q4Md8Nc66
# 06+Td6SDT4S51GLOAtzswkMFSQPyFlnbfn5koQ0s+a2tQ1N2pHkHmH/IwYdyupNT
# vp2HOzhrx2laMuO0mkdxKUq6/qa7zfF4323cAA5JRy/Wy11N8jGmRalN/MkFjcHx
# GOWe4HpFr3z2vo6w7oxes8UInMYoCMDcQE1lIjVcOIRIQ+cxeqjwAb2k4rS8IRj8
# R6okpLctOr9C3RhIdGP93FLZ7drl9Wtnr+gn
# SIG # End signature block
