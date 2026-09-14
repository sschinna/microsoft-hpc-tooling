<#
.Synopsis
    Moves HPC nodes to a target HPC Pack cluster.

.DESCRIPTION
    This script moves HPC nodes that meet the specified criteria to a target HPC Pack cluster. 

.NOTES
    Wildcard values for the ‘Name’ and ‘TemplateName’ parameters are not supported when 'NoSourceCluster' is specified
    Windows PowerShell remoting must be enabled in the HPC nodes when 'NoSourceCluster' is specified 

.EXAMPLE
    PS > Move-HpcNode.ps1 -Name HpcNode-* -TargetCluster "NewHN1,NewHN2,NewHN3"
    Moves HPC nodes named "HpcNode-*" from the current HPC cluster to a new HPC cluster with cluster connection string "NewHN1,NewHN2,NewHN3"
       
.EXAMPLE
    PS > Move-HpcNode.ps1 -Name HpcNode-1,HpcNode-2 -TargetCluster "NewHN1,NewHN2,NewHN3" -SourceCluster "OldHN1,OldHN2,OldHN3"
    Moves HPC nodes "HpcNode-1" and "HpcNode-2" from the HPC cluster "MyOldCluster" to HPC cluster "NewHN1,NewHN2,NewHN3"
       
.EXAMPLE
    PS > Move-HpcNode.ps1 -TemplateName NodeTemplate-* -TargetCluster MyNewCluster
    Moves all HPC nodes associated with HPC node template "NodeTemplate-*" to HPC cluster "MyNewCluster"

.EXAMPLE
    PS > Move-HpcNode.ps1 -Name HpcNode-1,HpcNode-2 -TargetCluster "NewHN1,NewHN2,NewHN3" -NoSourceCluster
    Moves HPC nodes "HpcNode-1" and "HpcNode-2" which don't belong to any HPC cluster currently to HPC cluster "NewHN1,NewHN2,NewHN3"
#>
 
[CmdletBinding(ConfirmImpact="Medium", DefaultParametersetName="Node", SupportsShouldProcess=$true)]
Param
(
    # A list of one or more names for the nodes that you want to move.
    [Parameter(Mandatory=$true, Position=0, ParameterSetName="Node")]
    [ValidateNotNullOrEmpty()]
    [String[]] $Name,

    # A list of names for the node templates that are associated with the nodes that you want to move. You cannot specify this parameter if 'NoSourceCluster' is specified.
    [Parameter(Mandatory=$true, Position=0, ParameterSetName="Template")]
    [ValidateNotNullOrEmpty()]
    [String[]] $TemplateName,

    # The target HPC Pack cluster connection string that you want the nodes moved to, for example "NewHN1,NewHN2,NewHN3".
    [Parameter(Mandatory=$true, Position=1)]
    [ValidateNotNullOrEmpty()]
    [String] $TargetCluster,

    # If specified, identifies the cluster connection string of the HPC cluster that currently includes the nodes. If you specify neither the 'SourceCluster' nor the 'NoSourceCluster' parameter, this cmdlet uses the CCP_SCHEDULER environment variable as the source HPC cluster connection string.
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [String] $SourceCluster,

    # If specified, indicates that no source HPC cluster is available (for example, the head node of the source cluster was destroyed).
    [Parameter(Mandatory=$false, ParameterSetName="Node")]
    [ValidateNotNullOrEmpty()]
    [Switch] $NoSourceCluster,

    # If specified, move the HPC nodes without confirmation prompt. 
    [Parameter(Mandatory=$false)]
    [Switch] $Force
)

$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"
$SetClusterScriptFile = "Set-HpcClusterName.ps1"
$StartTimestr = Get-Date -Format "MM_dd-HH_mm_ss"
$noHN = $NoSourceCluster.IsPresent
if(-not $noHN)
{
    if([String]::IsNullOrEmpty($SourceCluster))
    {
        $SourceCluster = $env:CCP_SCHEDULER
        if([String]::IsNullOrEmpty($SourceCluster))
        {
            Write-Error "You must use either 'SourceCluster' to specify the current cluster which the HPC cluster nodes belong to, or 'NoSourceCluster' if no current HPC cluster is available."
            return
        }
    }

    Add-PSSnapIn Microsoft.HPC
    if(-not $?)
    {
        throw "Failed to Load Microsoft.HPC SnapIn"
    }

    if ($PSCmdlet.ParameterSetName -eq "Node")
    {
        $hpcNodes = Get-HpcNode -Name $Name -Scheduler $SourceCluster -ErrorAction SilentlyContinue
    }
    else
    {
        foreach($tempName in $TemplateName)
        {
            if("HeadNode Template" -like $TemplateName)
            {
                Write-Warning "Cannot move an HPC head node."
            }
        }

        $hpcNodes = Get-HpcNode -TemplateName $TemplateName -Scheduler $SourceCluster -ErrorAction SilentlyContinue
    }

    if($hpcNodes -eq $null)
    {
        throw "No HPC cluster nodes can be moved."
    }

    $canMoveNodes = @()
    foreach($node in $hpcNodes)
    {
        if($node.IsHeadNode)
        {
            Write-Warning "$($node.NetbiosName) cannot be moved because it is a head node"
        }
        elseif(($node.NodeRole -band [Microsoft.ComputeCluster.CCPPSH.NodeCommand+NodeRole]::AzureWorkerNode) -gt 0)
        {
            Write-Warning "$($node.NetbiosName) cannot be moved because it is an Azure node"            
        }
        elseif(($node.NodeState -ne "Online") -and ($node.NodeState -ne "Offline") -and ($node.NodeState -ne "Draining"))
        {
            Write-Warning "$($node.NetbiosName) cannot be moved because it is in $($node.NodeState) state"
        }
        elseif($node.HealthState -eq "Error")
        {
            Write-Warning "$($node.NetbiosName) cannot be moved because it is unreachable"
        }
        else
        {
            $canMoveNodes += $node
        }
    }

    if($canMoveNodes.Count -eq 0)
    {
        throw "No HPC cluster nodes can be moved."
    }

    if(-not $Force.IsPresent)
    {
        $canMoveNodeNames = $canMoveNodes.NetbiosName -join ","
        if(-not $PsCmdlet.ShouldProcess("Move the HPC cluster nodes to another HPC cluster, the operation cannot be reverted",
                                        "The following HPC cluster nodes will be moved to the target HPC cluster $TargetCluster :`n $canMoveNodeNames`nDo you want to continue?",
                                        "Move HPC cluster nodes to HPC cluster $TargetCluster"))
        {
            return
        }
    }

    if($Force.IsPresent)
    {
        Set-HpcNodeState -Node $canMoveNodes -State offline -Scheduler $SourceCluster -Force -ErrorAction Continue | Out-Null
    }
    else
    {
        Set-HpcNodeState -Node $canMoveNodes -State offline -Scheduler $SourceCluster -ErrorAction Continue | Out-Null
    }

    $reminst = (Get-HpcClusterRegistry -Scheduler $SourceCluster -PropertyName InstallShare).Value
    # Use Clusrun.exe to schedule task on the selected HPC cluster nodes to update Cluster connection string, the HPC Services in the these nodes will eventually be restarted to make the Cluster connection string setting effective
    # We give 15 seconds delay so that the command can return before HPC Services restarted on these nodes.
    $tempScriptFile = "$reminst\Setup\Set-HpcClusterName-$StartTimestr.ps1"
    Copy-Item $PSScriptRoot\$SetClusterScriptFile $tempScriptFile -Force
    $clusrunParam = '/nodes:"{0}" /scheduler:{1} PowerShell.exe -ExecutionPolicy ByPass -Command "Copy-Item ''{2}'' $env:TEMP\Set-HpcClusterName.ps1 -Force; & $env:TEMP\Set-HpcClusterName.ps1 -ConnectionString {3} -Delay 15 -RunAsScheduledTask"' -f ($canMoveNodes.NetBiosName -join ","), $SourceCluster, $tempScriptFile, $TargetCluster
    Start-Process -FilePath "clusrun.exe" -ArgumentList $clusrunParam -Wait -NoNewWindow
    Remove-Item $tempScriptFile -Force -ErrorAction SilentlyContinue
    Remove-HpcNode -Node $canMoveNodes -Scheduler $SourceCluster -Confirm:$false
}
else
{
    if(-not [String]::IsNullOrEmpty($SourceCluster))
    {
        throw "You cannot specifiy both 'SourceCluster' and 'NoSourceCluster'"    
    }

    $wildcardNames = $Name | ?{$_ -match '[*, ?, \[, \]]'}
    if($wildcardNames -ne $null)
    {
        throw ("A wildCard Name is not supported when 'NoSourceCluster' is specified: " + ($wildcardNames -join ","))
    }

    if(-not $Force.IsPresent)
    {
        $tryMoveNames = $Name -join ","
        if(-not $PsCmdlet.ShouldProcess("Move the HPC cluster nodes to another HPC cluster, the operation cannot be reverted",
                                        "The following HPC cluster nodes will be moved to the target HPC cluster $TargetCluster :`n $tryMoveNames`nDo you want to continue?",
                                        "Move HPC cluster nodes to HPC cluster $TargetCluster"))
        {
            return
        }
    }

    $ThrottleLimit = 20
    $MaxRetry = 3
    $FailedNodes = @()

    $retryTable = @{}
    $waitingList = New-Object Collections.Generic.List[String]
    $Name | %{$waitingList.Add($_); $retryTable[$_]=0}
    $movingJobs = @()

    $scriptFilePath = "$PSScriptRoot\$SetClusterScriptFile"
    if(-not (Test-Path -Path $scriptFilePath -PathType Leaf))
    {
        $scriptFilePath = [System.IO.Path]::Combine($env:CCP_HOME, "Bin\$SetClusterScriptFile")
    }
    
    $scriptContent = $null
    if(Test-Path -Path $scriptFilePath -PathType Leaf)
    {
        $scriptContent = [IO.File]::ReadAllBytes($scriptFilePath)
    }
    else
    {
        throw "$SetClusterScriptFile not found"
    }

    while(($waitingList.Count -gt 0) -or ($movingJobs.Count -gt 0))
    {
        $runningJobs = @()
        foreach($job in $movingJobs)
        {
            $nodeName = $job.Name
            if($job.State -eq "Completed")
            {
                Write-Verbose "Successfully moved $nodeName to $TargetCluster"
                Remove-Job -Job $job
            }
            elseif($job.State -eq "Failed")
            {
                $failedReason = $job.ChildJobs[0].JobStateInfo.Reason
                if($failedReason -is [System.Management.Automation.Remoting.PSRemotingTransportException])
                {
                    if($retryTable[$nodeName] -lt $MaxRetry)
                    {
                        Write-Verbose "Failed to move $nodeName to $TargetCluster, retry later ..."
                        $waitingList.Add($nodeName)
                        $retryTable[$nodeName] += 1
                        Remove-Job -Job $job
                        continue
                    }
                }

                Write-Warning "Failed to move $nodeName to $TargetCluster : $failedReason"
                $FailedNodes += $nodeName
                Remove-Job -Job $job
            }
            else
            {
                $runningJobs += $job
            }
        }

        $movingJobs = $runningJobs

        $curJobCount = $movingJobs.Count
        if($curJobCount -ge $ThrottleLimit)
        {
            Start-Sleep -Seconds 2
            continue
        }
        
        $leftCapacity = $ThrottleLimit - $curJobCount
        while(($leftCapacity -gt 0) -and ($waitingList.Count -gt 0))
        {
            $nodeName = $waitingList[0]
            $waitingList.RemoveAt(0) | Out-Null
            Write-Verbose "Moving HPC Node $nodeName ..."
            $movingJobs += Invoke-Command -ComputerName $nodeName -ScriptBlock {
                param([String]$clusName, [Byte[]]$scriptContent)
                
                $SetClusterScriptFile = "$env:temp\Set-HpcClusterName.ps1"
                if(Test-Path -Path $SetClusterScriptFile -PathType Leaf)
                {
                    Remove-Item $SetClusterScriptFile -Force
                }

                try
                {
                    [IO.File]::WriteAllBytes($SetClusterScriptFile, $scriptContent)
                }
                catch
                {
                    throw "Failed to create Set-HpcClusterName.ps1"
                }

                $process = Start-Process -FilePath "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -Command `"& '$SetClusterScriptFile' $clusName`"" -PassThru -Wait
                if($process.ExitCode -ne 0)
                {
                    throw "Failed to update HPC cluster connection string: $($process.ExitCode)"
                }

            } -ArgumentList @($TargetCluster, $scriptContent) -AsJob -JobName $nodeName

            $leftCapacity--
        }
    }

    if($FailedNodes.Count -gt 0)
    {
        Write-Error "The following nodes were not moved to $TargetCluster :`n $FailedNodes" 
    }
}

# SIG # Begin signature block
# MIIdhwYJKoZIhvcNAQcCoIIdeDCCHXQCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUMeZooGlp3JxmXQZWdXuExW8y
# gaWgghhjMIIE3jCCA8agAwIBAgITMwAAAVMi29XcAx7KbwAAAAABUzANBgkqhkiG
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
# AgEVMCMGCSqGSIb3DQEJBDEWBBTAfc+RU5y6jVoo5j1ILA5Nk7GGbTBCBgorBgEE
# AYI3AgEMMTQwMqAUgBIATQBpAGMAcgBvAHMAbwBmAHShGoAYaHR0cDovL3d3dy5t
# aWNyb3NvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBAG1odDn33RwYWGKiPOqXhM4H
# j1tLFd8TTceIdHjbYvivpmsDVUFLm708IQxcZKK7+2UU5gWKWZmD88Otd0To5OKg
# r/qPGZqrOvfDZ6QR82TwdmFhubz1miQ1xj7PfYLRPWqGsfBopxaShE/oHVWBnqrI
# tPvzGMUnglgoCDgweT0HvRTNAWaKHZGzuP5kEeEG8kwKRs75Ym/UVbV6Gi4UdpHA
# T6P83zmUoB0+h4tl9zUzw9wtGLqbPuopt6H4RixM4N+PPZrxJV8ipg6QVqrLjPb8
# jCrs+NAPfTHyPw/Dr1JRd5cc4/UVcasxGw9zuyHuAUGHvCKAtXmtXEycUNjF3YSh
# ggIoMIICJAYJKoZIhvcNAQkGMYICFTCCAhECAQEwgY4wdzELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEhMB8GA1UEAxMYTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgUENBAhMzAAABUyLb1dwDHspvAAAAAAFTMAkGBSsOAwIaBQCgXTAYBgkq
# hkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yMDA2MDcxMjM2
# MzRaMCMGCSqGSIb3DQEJBDEWBBTc4se9v6nndgOnCgsz2r/hZv9/UTANBgkqhkiG
# 9w0BAQUFAASCAQAj1GSJxwynZxFt9cnQGmn7GaRDlVsJRTRFHYex5ZWYkxTMNOjr
# tN4bsuFYE2PyLrNLrkpW7mnwDbYt+MimqV5aLe0lbLpfvMw8Fv3Oy4jJFc7E/QJr
# WrOZYJ7gvl+k+Uk9fjjy7EVUV5O3dbg0q44LlJN/N/YDZNKcvawGYItcHPPRNnoH
# nEtFR3cPHqctNpY0UrWjQLsw7b0pl1tGAwJes95Xthih1HZgXvlX9ddj1IVqBO/Q
# qk9OWN3Af68KQ1+dGbvXIaEySibRlvRvbcRwlcxO12X+1wqvQV8hjrcau9D6TRDr
# O7Y8XGXvbUnmvqTGqqLMVaBBfw/ccMGrAbwa
# SIG # End signature block
