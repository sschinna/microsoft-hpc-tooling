
# ----------------------------------------------------------------------------- 
# Script: AzureAutoGrowShrink.ps1
# Author: Microsoft HPC Pack team
# Version: 4.4
# Keywords: HPC, Azure PaaS instances, Azure IaaS VMs, auto grow and shrink
# Comments: 
# ----------------------------------------------------------------------------- 

<# 
   .Synopsis 
    This script is used to automatically grow and shrink PaaS Azure nodes and IaaS Azure VMs in a Microsoft HPC Pack cluster based on the workload (jobs/tasks) in the cluster

   .Parameter NodeTemplates
    Specifies the names of the node templates to define the scope for the nodes to grow and shrink. If not specified (the default value is @()), all nodes in the 'AzureNodes' node group are in scope for the node type 'AzureNodes', and all nodes in the 'ComputeNodes' node group are in scope for the node type 'ComputeNodes'

   .Parameter JobTemplates
    Specifies the names of the job templates to define the workload for which the nodes to grow. If not specified (the default value is @()), all active jobs are in scope for check.

   .Parameter NodeType
    Specifies the node types to grow and shrink. The default value is 'AzureNodes' for PaaS Azure burst nodes in both on-premises and Azure IaaS clusters. If specified as 'ComputeNodes', the nodes would be Azure IaaS VMs only on IaaS clusters.

   .Parameter NumOfQueuedJobsPerNodeToGrow
    The number of queued jobs required to grow one node

   .Parameter NumOfQueuedJobsToGrowThreshold
    The threshold number of queued jobs to start the grow process

   .Parameter NumOfActiveQueuedTasksPerNodeToGrow
    The number of active queued tasks required to grow one node. If NumOfQueuedJobsPerNodeToGrow is specified with a value greater than 0, this parameter is ignored.

   .Parameter NumOfActiveQueuedTasksToGrowThreshold
    The threshold number of active queued tasks to start the grow process

   .Parameter NumOfInitialNodesToGrow
    The initial minimum number of nodes to grow if all the nodes in scope are NotDeployed or Stopped(Deallocated)

   .Parameter GrowCheckIntervalMins
    The interval in minutes between checks to grow.

   .Parameter ShrinkCheckIntervalMins
    The interval in minutes between checks to shrink. 

   .Parameter ShrinkCheckIdleTimes
    The number of continuous shrink checks (separated by ShrinkCheckIntervalMins) to indicate the nodes are idle

   .Parameter UseLastConfigurations
    Switch to use the previous configurations saved in the argument file

   .Parameter ArgFile
    Specifies the name of the argument file used to save and update the configurations to run the script

   .Parameter LogFilePrefix
    Specifies the prefix name of the log file, you can include the path, by default the log will be in current working directory

   .Parameter ExtraNodesGrowRatio
    Specifies additional nodes to grow, because it can take a long time to start certain Azure nodes to reach a growth target. The default value is 0. For example, a value of 10 indicates that the cluster will grow 110% of the nodes.

   .Example 
    .\AzureAutoGrowShrink.ps1 -NodeTemplates @('Default AzureNode Template') -NodeType AzureNodes -NumOfQueuedJobsPerNodeToGrow 10 -NumOfQueuedJobsToGrowThreshold 10 -NumOfInitialNodesToGrow 2 -GrowCheckIntervalMins 5 -ShrinkCheckIntervalMins 5 -ShrinkCheckIdleTimes 3 

   .Example  
    .\AzureAutoGrowShrink.ps1 -NodeTemplates 'AzureNode Template 1','AzureNode Template 2' -JobTemplates 'Job Template 1' -NodeType ComputeNodes -NumOfActiveQueuedTasksPerNodeToGrow 20 -GrowCheckIntervalMins 5 -ShrinkCheckIntervalMins 10 -LogFilePrefix C:\LogFiles\MyAutoGrowShrinkLog

   .Notes 
    The prerequisites for running this script:
    1. Add the Azure nodes or the Azure VMs before running the script.
    2. If using Azure VMs, the cluster should be in the IaaS environment. 
    3. The HPC cluster should be running HPC Pack 2012 R2 Update 1 or later

   .Link 

#>

param (

[Parameter (Mandatory=$False)]
[string[]] 
$NodeTemplates=@(),

[Parameter (Mandatory=$False)]
[string[]] 
$JobTemplates=@(),

[Parameter (Mandatory=$False)]
[ValidateSet("AzureNodes", "ComputeNodes")]
[String]
$NodeType="AzureNodes",

[Parameter (Mandatory=$False)] 
[ValidateRange(0,[Float]::MaxValue)]
[Float] 
$NumOfQueuedJobsPerNodeToGrow=0, 

[Parameter (Mandatory=$False)]
[ValidateRange(0,[Int]::MaxValue)]
[Int] 
$NumOfQueuedJobsToGrowThreshold=0, 

[Parameter (Mandatory=$False)]
[ValidateRange(0,[Float]::MaxValue)]
[Float] 
$NumOfActiveQueuedTasksPerNodeToGrow=0, 

[Parameter (Mandatory=$False)]
[ValidateRange(0,[Int]::MaxValue)]
[Int] 
$NumOfActiveQueuedTasksToGrowThreshold=0, 

[Parameter (Mandatory=$False)]
[ValidateRange(1,[Int]::MaxValue)]
[Int] 
$NumOfInitialNodesToGrow=2, 

[Parameter (Mandatory=$False)]
[ValidateRange(1,[Int]::MaxValue)]
[int] 
$GrowCheckIntervalMins=1, 

[Parameter (Mandatory=$False)]
[ValidateRange(1,[Int]::MaxValue)]
[int] 
$ShrinkCheckIntervalMins=2,

[Parameter (Mandatory=$False)]
[ValidateRange(1,[Int]::MaxValue)]
[int]
$ShrinkCheckIdleTimes=3,

[Parameter (Mandatory=$False)]
[Switch]
$UseLastConfigurations,

[Parameter (Mandatory=$False)]
[String]
$ArgFile="AzureAutoGrowShrink_Arg.xml",

[Parameter (Mandatory=$False)]
[String]
$LogFilePrefix="AzureAutoGrowShrink_Log",

[Parameter (Mandatory=$False)]
[int]
$ExtraNodesGrowRatio=0
)

# Private function to retrieve the intersection of multiple string arrays
Function Intersect
{
    Param
    (
        [String[][]] $stringArrays
    )
    [String[]] $stringArray=$null;
    if ($null -eq $stringArrays -or $stringArrays.Count -eq 0)
    {
        return @();
    }
    foreach ($array in $stringArrays)
    {
        if ($null -eq $array -or $array.Count -eq 0)
        {
            $stringArray=@();
            break;
        }
        if ($null -eq $stringArray)
        {
            $stringArray = $array;
        }
        else
        {
            $stringArray = @($stringArray | ? { $array.Contains($_) })
        }
    }
    $stringArray;
}

# Private function to retrieve the union of multiple string arrays
Function Union
{
    Param
    (
        [String[][]] $stringArrays
    )
    [String[]] $stringArray = @();
    foreach ($array in $stringArrays)
    {
        $stringArray += $array
    }
    $stringArray | select -Unique;
}

# Private function to retrieve the uniform of multiple string arrays
Function Uniform
{
    Param
    (
        [String[][]] $stringArrays
    )
    [String[]] $unionArray = $null;
    [String[]] $intersectArray = @();
    foreach ($array in $stringArrays)
    {
        if ($null -eq $unionArray)
        {
            $unionArray = $array;
        }
        else
        {
            $intersectArray = Union @($intersectArray, (Intersect @($array, $unionArray)))
            $unionArray = Union @($unionArray, $array)
        }
    }
    if ($null -eq $unionArray)
    {
        $unionArray = @();
    }

    @( $unionArray | ? { -not $intersectArray.Contains($_) } )
}

Function GetLogFileName
{
    $datetimestr = (Get-Date).ToString("yyyyMMdd")        
    return [string]::Format("{0}_{1}.log", $LogFilePrefix, $datetimestr)
}

# Private function to log info
Function LogInfo
{
    Param (
    [String]
    $message
    )

    $LogDate=Get-Date -Format 'MM/dd/yyyy HH:mm:ss' 
    $message="[$LogDate][Info] $message"

    Write-Host $message
    $message >> $(GetLogFileName)
}

# Private function to log warning
Function LogWarning
{
    Param (
    [String]
    $message
    )

    $LogDate = Get-Date -Format 'MM/dd/yyyy HH:mm:ss' 
    $message = "[$LogDate][Warning] $message"

    Write-Host -ForegroundColor Yellow $message
    $message >> $(GetLogFileName)
}

# Private function to log error
Function LogError
{
    Param (
    [String]
    $message
    )

    $LogDate = Get-Date -Format 'MM/dd/yyyy HH:mm:ss' 
    $message = "[$LogDate][Error] $message"

    Write-Host -ForegroundColor Red $message
    $message >> $(GetLogFileName)

}

# Print scroll while waiting
Function WaitScroll
{
    Param(
    [Int]
    $waitTimeSec  = 10
    )

    $scrollChars = "/-\|"
    $LogDate = Get-Date -Format 'MM/dd/yyyy HH:mm:ss' 
    Write-Host "[$LogDate]" -NoNewline
    for($i = 0; $i -lt $waitTimeSec*5; $i++)
    {
        Write-Host -NoNewline -ForegroundColor Green $scrollChars[$i%4];
        $cursorPos = $host.UI.RawUI.CursorPosition;
        $cursorPos.X -= 1;
        $host.UI.RawUI.CursorPosition = $cursorPos;

        sleep -Milliseconds 200

    }
    $cursorPos = $host.UI.RawUI.CursorPosition;
    $cursorPos.X -= 21;
    $host.UI.RawUI.CursorPosition = $cursorPos
    
}

# Print the argument list
Function PrintArgs
{
    Param(
    $argObject
    )
    if ($null -ne $argObject)
    {
        LogInfo "Script arguments :"
        $nodeTemplateString = "";
        foreach ($template in $argObject.NodeTemplates)
        {
            $nodeTemplateString += "[$template]";
        }
        $jobTemplateString = "";
        foreach ($template in $argObject.JobTemplates)
        {
            $jobTemplateString += "[$template]";
        }
        LogInfo ("NodeTemplates -- [{0}]" -f $nodeTemplateString)
        LogInfo ("JobTemplates -- [{0}]" -f $jobTemplateString)
        LogInfo ("NodeType -- [{0}]" -f $argObject.NodeType)
        LogInfo ("NumOfQueuedJobsPerNodeToGrow -- [{0}]" -f $argObject.NumOfQueuedJobsPerNodeToGrow)
        LogInfo ("NumOfQueuedJobsToGrowThreshold -- [{0}]" -f $argObject.NumOfQueuedJobsToGrowThreshold)
        LogInfo ("NumOfActiveQueuedTasksPerNodeToGrow -- [{0}]" -f $argObject.NumOfActiveQueuedTasksPerNodeToGrow)
        LogInfo ("NumOfActiveQueuedTasksToGrowThreshold -- [{0}]" -f $argObject.NumOfActiveQueuedTasksToGrowThreshold)
        LogInfo ("NumOfInitialNodesToGrow -- [{0}]" -f $argObject.NumOfInitialNodesToGrow)
        LogInfo ("GrowCheckIntervalMins -- [{0}]" -f $argObject.GrowCheckIntervalMins)
        LogInfo ("ShrinkCheckIntervalMins -- [{0}]" -f $argObject.ShrinkCheckIntervalMins)
        LogInfo ("ShrinkCheckIdleTimes -- [{0}]" -f $argObject.ShrinkCheckIdleTimes)

    }
}

# Check the argument list
Function CheckArgs
{
    Param(
    $argObject
    )
    if ($null -eq $argObject)
    {
        LogError "Arguments are not available for check";
        return $false;
    }
    #check the Scheduler name
    if ([String]::IsNullOrEmpty($env:CCP_SCHEDULER) -or @(Get-HpcNode -GroupName HeadNodes -ErrorAction SilentlyContinue).Count -eq 0)
    {
        LogError "The scheduler '$env:CCP_SCHEDULER' cannot be connected. Please check it."
        return $false;
    }
    
    $allExist=$true;
    #check the node templates
    $existingNodeTemplates = @(Get-HpcNodeTemplate -ErrorAction SilentlyContinue | % {$_.Name})
    foreach ($template in $argObject.NodeTemplates)
    {
        if ($template -notin $existingNodeTemplates)
        {
            LogError "The node template name '$template' doest not exist. Please check it."
            $allExist = $false; 
        }
    }
    #check the job templates
    $existingJobTemplates = @(Get-HpcJobTemplate -ErrorAction SilentlyContinue | % {$_.Name})
    foreach ($template in $argObject.JobTemplates)
    {
        if ($template -notin $existingJobTemplates)
        {
            LogError "The job template name '$template' doest not exist. Please check it."
            $allExist = $false; 
        }
    }
    return $allExist;

}

# Print the nodes
Function PrintNodes
{
    Param(
    $nodes = @()
    )
    $formatString = "{0,16}{1,12}{2,15}{3,10}{4,20}";
    LogInfo ($formatString -f "NetBiosName","NodeState","NodeHealth","Weight","Groups")
    LogInfo ($formatString -f "-----------","---------","----------","------","------")
    foreach ($node in $nodes)
    {
        LogInfo ($formatString -f $node.NetBiosName,$node.NodeState,$node.NodeHealth,$node.RequestedWeight,$node.Groups)
    }
}

# Start nodes in background jobs
Function StartNodes
{
    Param(
    [ScriptBlock]
    $StartScript,

    [String[]]
    $Nodes,
    
    [Int]
    $WaitTimeMins
    )
    
    $job = Start-Job -Name 'Start HPC Nodes' -ScriptBlock $StartScript -ArgumentList @(,$Nodes)
    $i = 0;
    for(;$i -lt $WaitTimeMins;$i++)
    {
        
        if ($job.State -eq 'Completed')
        {
            $results = @(Receive-Job -Job $job)
            
            if ($results[-1] -eq $true)
            {
                LogInfo "Start nodes succeeded"
            }
            else
            {
                LogInfo "Start nodes failed"
                LogInfo $results[-2]
            }
            $onlineNodes = @(Get-HpcNode -Name $Nodes -State Offline -ErrorAction SilentlyContinue | Set-HpcNodeState -State online -ErrorAction SilentlyContinue)
            if ($onlineNodes.Count -gt 0)
            {
                LogInfo "Nodes online : $(@($onlineNodes | % { $_.NetBiosName }))"
            }
            WaitScroll 60
            break;
        }

        $onlineNodes = @(Get-HpcNode -Name $Nodes -State Offline -ErrorAction SilentlyContinue | Set-HpcNodeState -State online -Async -ErrorAction SilentlyContinue)
        if ($onlineNodes.Count -gt 0)
        {
            LogInfo "Nodes online : $(@($onlineNodes | % { $_.NetBiosName }))"
        }
        WaitScroll 60
        
    }

    if ($i -eq $WaitTimeMins)
    {
        LogWarning "Start Nodes PS job timed out with state $($job.state)"
    }

}

# Wait IaaS nodes to start
Function WaitNodes
{
    Param(    
    [String[]]
    $Nodes,

    [Int]
    $WaitTimeMins
    )
    LogInfo "Wait for nodes to start."
    $i = 0;
    $count =@(Get-HpcNode -Name $Nodes -State Offline -HealthState Error -ErrorAction SilentlyContinue).Count;
    for(;$i -lt $WaitTimeMins;$i++)
    {
        $okNodes = @(Get-HpcNode -Name $Nodes -State Offline -HealthState OK -ErrorAction SilentlyContinue | Set-HpcNodeState -State online -ErrorAction SilentlyContinue)
        
        if ($okNodes.Count -gt 0)
        {
            LogInfo "Nodes online : $(@($okNodes | % { $_.NetBiosName }))"
            $count-=$okNodes.Count;
        }

        if ($count -eq 0)
        {
            LogInfo "All growing nodes are online."
            break;
        }

        WaitScroll 60
    }
}

Add-PSSnapin microsoft.hpc;

$lastCheckToGrow = Get-Date;
$lastCheckToShrink = Get-Date;
$idleNodesHistory = @();

$growingIaaSNodes = @{}
$AllNodesNeededForQueuedJobTask = @()

$NodeTypes = New-Object -TypeName System.Object
$NodeTypes | Add-Member -MemberType NoteProperty -Name 'AzureNodes' -Value 'AzureNodes' -TypeName String
$NodeTypes | Add-Member -MemberType NoteProperty -Name 'ComputeNodes' -Value 'ComputeNodes' -TypeName String

# init the log file
$LogFile = GetLogFileName
"AzureAutoGrowShrink Init @ $(Get-Date) on HPC Cluster [$env:CCP_SCHEDULER]" >> $LogFile

LogInfo "Log file : $LogFile"
LogInfo "Argument file : $ArgFile"

# save the parameter file
$lastArgFileReadTime =  [DateTime]::MinValue;
if (-not $UseLastConfigurations)
{
    $argObject = New-Object -TypeName System.Object;
    $argObject | Add-Member -MemberType NoteProperty -TypeName String[] -Name NodeTemplates -Value $NodeTemplates
    $argObject | Add-Member -MemberType NoteProperty -TypeName String[] -Name JobTemplates -Value $JobTemplates
    $argObject | Add-Member -MemberType NoteProperty -TypeName String -Name NodeType -Value $NodeType
    $argObject | Add-Member -MemberType NoteProperty -TypeName Int -Name NumOfQueuedJobsPerNodeToGrow -Value $NumOfQueuedJobsPerNodeToGrow
    $argObject | Add-Member -MemberType NoteProperty -TypeName Int -Name NumOfQueuedJobsToGrowThreshold -Value $NumOfQueuedJobsToGrowThreshold
    $argObject | Add-Member -MemberType NoteProperty -TypeName Int -Name NumOfActiveQueuedTasksPerNodeToGrow -Value $NumOfActiveQueuedTasksPerNodeToGrow
    $argObject | Add-Member -MemberType NoteProperty -TypeName Int -Name NumOfActiveQueuedTasksToGrowThreshold -Value $NumOfActiveQueuedTasksToGrowThreshold
    $argObject | Add-Member -MemberType NoteProperty -TypeName Int -Name NumOfInitialNodesToGrow -Value $NumOfInitialNodesToGrow
    $argObject | Add-Member -MemberType NoteProperty -TypeName Int -Name GrowCheckIntervalMins -Value $GrowCheckIntervalMins
    $argObject | Add-Member -MemberType NoteProperty -TypeName Int -Name ShrinkCheckIntervalMins -Value $ShrinkCheckIntervalMins
    $argObject | Add-Member -MemberType NoteProperty -TypeName Int -Name ShrinkCheckIdleTimes -Value $ShrinkCheckIdleTimes
    
    $argObject | Export-Clixml -Path $ArgFile;
    $lastArgFileReadTime = (gi -Path $ArgFile).LastWriteTime;

    PrintArgs $argObject

    # check node templates
    if ((CheckArgs $argObject) -eq $false)
    {
        LogError "Argument check failed. Please correct it and retry."
        exit -1 
    }
}

while ($True)
{
    $checkToGrow = $false;
    $checkToShrink = $false;    
    $now = Get-Date;

    # check if the ArgFile is modified, if yes, update the args from the ArgFile
    $lastArgFileWriteTime = (gi -Path $ArgFile).LastWriteTime;
    $argUpdated = $lastArgFileWriteTime -gt $lastArgFileReadTime;

    if ($argUpdated)
    {
        $argObject = Import-Clixml -Path $ArgFile
        
        $NodeTemplates = $argObject.NodeTemplates;
        $JobTemplates = $argObject.JobTemplates;
        $NodeType = $argObject.NodeType;
        $NumOfQueuedJobsPerNodeToGrow = $argObject.NumOfQueuedJobsPerNodeToGrow;
        $NumOfQueuedJobsToGrowThreshold = $argObject.NumOfQueuedJobsToGrowThreshold;        
        $NumOfActiveQueuedTasksPerNodeToGrow = $argObject.NumOfActiveQueuedTasksPerNodeToGrow;
        $NumOfActiveQueuedTasksToGrowThreshold = $argObject.NumOfActiveQueuedTasksToGrowThreshold;
        $NumOfInitialNodesToGrow = $argObject.NumOfInitialNodesToGrow;
        $GrowCheckIntervalMins = $argObject.GrowCheckIntervalMins;
        $ShrinkCheckIntervalMins = $argObject.ShrinkCheckIntervalMins;
        $ShrinkCheckIdleTimes = $argObject.ShrinkCheckIdleTimes;
        
        $lastArgFileReadTime = $lastArgFileWriteTime

        LogInfo "The arguments are loaded from the argument file."
        
        PrintArgs $argObject
    }

    # check if it is time to check grow
    if ($GrowCheckIntervalMins -gt 0 -and ($now - $lastCheckToGrow).TotalMinutes -gt $GrowCheckIntervalMins)
    {
        $checkToGrow = $true;
    }

    # check if it is time to check shrink
    if ($ShrinkCheckIntervalMins -gt 0 -and ($now - $lastCheckToShrink).TotalMinutes -gt $ShrinkCheckIntervalMins)
    {
        $checkToShrink = $true;
    }
    
    # calculate the resource to grow
    if ($checkToGrow)
    {
        LogInfo "===============Grow Check==================" 

        $AllNodesNeededForQueuedJobTask = @()
        $lastCheckToGrow = Get-Date;
        
        # retrieve queued jobs/tasks
        $activeJobs = @()
        
        if ($JobTemplates.Count -ne 0)
        {
            foreach ($jobTemplate in $JobTemplates)
            {
                $activeJobs += @(Get-HpcJob -State Running,Queued -TemplateName $jobTemplate -ErrorAction SilentlyContinue)
            }
        }
        else
        {
            $activeJobs = @(Get-HpcJob -State Running,Queued -ErrorAction SilentlyContinue)
        }

        $queuedJobs = @($activeJobs | ? { $_.State -eq 'Queued' })
        $numOfActiveJobs = $activeJobs.Count;
        $numOfQueuedJobs = $queuedJobs.Count;
        LogInfo "Number of active jobs : $numOfActiveJobs"
        LogInfo "Number of queued jobs : $numOfQueuedJobs"

        $nodesToGrow = @()

        # Initial check for numOfQueuedJobs and numOfActiveJobs
        if ( ($NumOfQueuedJobsPerNodeToGrow -gt 0 -and $numOfQueuedJobs -gt $NumOfQueuedJobsToGrowThreshold) -or ($NumOfQueuedJobsPerNodeToGrow -eq 0 -and $NumOfActiveQueuedTasksPerNodeToGrow -gt 0 -and $numOfActiveJobs -gt 0))
        {
            # obtain all the nodes in the scope to grow and shrink
            $azureNodes = @();

            if ($NodeTemplates.Count -ne 0)
            {
                $azureNodes = @(Get-HpcNode -GroupName $NodeType -TemplateName $NodeTemplates -ErrorAction SilentlyContinue)
            }
            else
            {
                $azureNodes = @(Get-HpcNode -GroupName $NodeType -ErrorAction SilentlyContinue)
            }
            
            $nodesNamed = @{};
            $nodesGrouped = @{};
            $nodesTemplated = @{};
            # Check if all the nodes in scope are NotDeployed or Stopped(Deallocated) so that the NumOfInitialNodesToGrow should apply
            $allNodesNotDeployedOrStopped = $true;

            $CoresPerNode = 32
            $SocketsPerNode = 4

            foreach ($node in $azureNodes)
            {
                Add-Member -InputObject $node -MemberType NoteProperty -Name 'RequestedWeight' -Value 0.0;
            
                if ( ($NodeType -eq $NodeTypes.AzureNodes -and $node.NodeState -ne 'NotDeployed') -or ($NodeType -eq $NodeTypes.ComputeNodes -and ($node.HealthState -ne 'Error' -or $node.NodeState -ne 'Offline')))
                {
                    $allNodesNotDeployedOrStopped = $false
                }

                if($null -ne $node.ProcessorCores -and $node.ProcessorCores -gt 0 -and  $node.ProcessorCores -lt $CoresPerNode)
                {
                    $CoresPerNode = $node.ProcessorCores
                }

                if($null -ne $node.Sockets -and $node.Sockets -gt 0 -and $node.Sockets -lt $SocketsPerNode)
                {
                    $SocketsPerNode = $node.Sockets
                }
                
                $nodesNamed[$node.NetBiosName] = $node;
                $nodeGroups = @($node.Groups.Split(',',[StringSplitOptions]::RemoveEmptyEntries));
                foreach ($group in $nodeGroups)
                {
                    if ($nodesGrouped.ContainsKey($group))
                    {
                        if ($nodesGrouped[$group].Contains($node))
                        {
                            continue;
                        }
                        else
                        {
                            $nodesGrouped[$group] += $node;
                        }
                    }
                    else
                    {
                        $nodesGrouped[$group] = @($node);
                    }
                }

                if ($nodesTemplated.ContainsKey($node.Template))
                {
                    $nodesTemplated[$node.Template] += $node;
                }
                else
                {
                    $nodesTemplated[$node.Template] = @($node);
                }
            }

            # Check if there are nodes in scope
            if ($azureNodes.Count -gt 0)
            {
                # grow with number of queued jobs
                if ($NumOfQueuedJobsPerNodeToGrow -gt 0)
                {
                    LogInfo "Grow with queued jobs"
                    
                    $numOfIrrelevantJobs = 0;
                    
                    $requiredNodeNumber = 0;
                    # get queued jobs and calculate the nodes requested
                    foreach ($job in $queuedJobs)
                    {
                        $jobNodeGroups = @()
                        $jobNodeGroupNodes = @()
                        $jobNodeGroupRequestedNodes = @()
                        
                        if (-not [String]::IsNullOrEmpty($job.NodeGroups))
                        {
                            $jobNodeGroups += $job.NodeGroups.Split(',',[StringSplitOptions]::RemoveEmptyEntries);
                    
                            foreach ($jobNodeGroup in $jobNodeGroups)
                            {
                                if ($nodesGrouped.ContainsKey($jobNodeGroup))
                                {
                                    $jobNodeGroupNodes+=,@($nodesGrouped[$jobNodeGroup] | % { $_.NetBiosName })
                                }
                            }

                            switch ($job.NodeGroupOp)
                            {
                                "Intersect"
                                {
                                    $jobNodeGroupRequestedNodes += Intersect $jobNodeGroupNodes;
                                }
                                "Union"
                                {
                                    $jobNodeGroupRequestedNodes += Union $jobNodeGroupNodes;
                                }
                                "Uniform"
                                {
                                    $jobNodeGroupRequestedNodes += Uniform $jobNodeGroupNodes;
                                }
                                default
                                { }
                            }
                        }
                        else # if job is not specified with any node group, consider it requesting all the nodes
                        {
                            $jobNodeGroupRequestedNodes += @($azureNodes | % { $_.NetBiosName });
                        }

                        $jobRequestedNodes = @()
                        if ($null -ne $job.RequestedNodes)
                        {
                            $jobRequestedNodes += $job.RequestedNodes.Split(',',[StringSplitOptions]::RemoveEmptyEntries);
                        }
                    
                        if ($jobRequestedNodes.Count -eq 0)
                        {
                            $requestedNodes = $jobNodeGroupRequestedNodes;
                        }
                        else
                        {
                            $requestedNodes =  Intersect @($jobNodeGroupRequestedNodes, $jobRequestedNodes);
                        }

                        # Add weights for the requested nodes
                        if ($requestedNodes.Count -ne 0)
                        {
                            $weight = 1.0/$requestedNodes.Count
                            foreach ($node in $requestedNodes)
                            {
                                $nodesNamed[$node].RequestedWeight += $weight;
                            }

                            switch($job.UnitType)
                            {
                                "Node" { $requiredNodeNumber += [math]::Max($job.MinNodes, 1/$NumOfQueuedJobsPerNodeToGrow) }
                                "Socket" { $requiredNodeNumber += [math]::Max($job.MinSockets/$SocketsPerNode, 1/$NumOfQueuedJobsPerNodeToGrow) }
                                "Core" { $requiredNodeNumber += [math]::Max($job.MinCores/$CoresPerNode, 1/$NumOfQueuedJobsPerNodeToGrow) }
                                default {}
                                    
                            }
                        }
                        else
                        {
                            $numOfIrrelevantJobs++;
                        }
                    } # end of foreach queued jobs

                    $numOfRelevantJobs = $numOfQueuedJobs-$numOfIrrelevantJobs;
                    LogInfo "Number of relevant queued jobs : $numOfRelevantJobs"

                    # if relevant queued jobs exceeds the threshold
                    if ($numOfRelevantJobs -gt $NumOfQueuedJobsToGrowThreshold)
                    {
                        # calculate how many nodes to grow
                        $numOfNodesToGrow = [math]::Ceiling($requiredNodeNumber*(1+$ExtraNodesGrowRatio/100))
                        if ($numOfNodesToGrow -lt $NumOfInitialNodesToGrow -and $allNodesNotDeployedOrStopped)
                        {
                            $numOfNodesToGrow = $NumOfInitialNodesToGrow;
                        }

                        # check idle nodes for now
                        $idleAzureNodesToCheck = @($azureNodes | ? { $_.NodeState -eq 'Online' -and $_.HealthState -eq 'OK' })
                        $idleAzureNodes = @();
                        foreach ($node in $idleAzureNodesToCheck)
                        {
                            $jobCount = (Get-HpcJob -NodeName $node.NetBiosName -ErrorAction SilentlyContinue).Count;
                            if ($jobCount -eq 0)
                            {
                                $idleAzureNodes += $node.NetBiosName;
                            }
                        }

                        # sort the nodes by weight and choose the nodes            
                        $azureNodesSorted = @($azureNodes | sort -Property @{Expression="RequestedWeight";Descending=$true},@{Expression="NodeState";Descending=$false} | ? { $_.NodeState -eq 'NotDeployed' -or $_.NodeState -eq 'Offline' -or $idleAzureNodes -ccontains $_.NetBiosName })

                        LogInfo "Nodes to grow capacity : $($azureNodesSorted.Count)"

                        if ($numOfNodesToGrow -gt $azureNodesSorted.Count)
                        {
                            $numOfNodesToGrow = $azureNodesSorted.Count;
                        }

                        # choose the number of nodes with weight
                        $AllNodesNeededForQueuedJobTask = @($azureNodesSorted[0..($numOfNodesToGrow-1)] | ? {$_.RequestedWeight -gt 0.0})
                        $nodesToGrow = $AllNodesNeededForQueuedJobTask | ?{$_.NodeState -ne 'Online'}
                        
                        # bring offline nodes if any
                        $nodesToGrowByBringOnline = @($nodesToGrow | ? {$_.NodeState -eq 'Offline' -and $_.HealthState -eq 'OK'})
                        if ($nodesToGrowByBringOnline.Count -gt 0)
                        {
                            LogInfo "Grow nodes by bringing online : $($nodesToGrowByBringOnline.Count)"
                            Set-HpcNodeState -Node $nodesToGrowByBringOnline -State online -ErrorAction SilentlyContinue | Out-Null
                            $nodesToGrow = @($nodesToGrow | ? {$nodesToGrowByBringOnline -notcontains $_})
                        }
                        
                        LogInfo "Nodes to grow for relevant queued jobs : $($nodesToGrow.Count), required node number : $([math]::Ceiling($requiredNodeNumber))"
                    }            
                }
                # grow with number of active queued tasks
                elseif ($NumOfActiveQueuedTasksPerNodeToGrow -gt 0)
                {
                    LogInfo "Grow with active queued tasks"
                    # get active jobs and calculate the nodes requested
                    $totalNumOfRelevantQueuedTasks = 0;
                    $numOfIrrelevantJobs = 0;
                    
                    $requiredNodeNumber = 0
                    foreach ($job in $activeJobs)
                    {
                        $jobNodeGroups = @()
                        $jobNodeGroupNodes = @()
                        $jobNodeGroupRequestedNodes = @()
                        
                        if (-not [String]::IsNullOrEmpty($job.NodeGroups))
                        {
                            $jobNodeGroups += $job.NodeGroups.Split(',',[StringSplitOptions]::RemoveEmptyEntries);
                
                            foreach ($jobNodeGroup in $jobNodeGroups)
                            {
                                if ($nodesGrouped.ContainsKey($jobNodeGroup))
                                {
                                    $jobNodeGroupNodes+=,@($nodesGrouped[$jobNodeGroup] | % { $_.NetBiosName })
                                }
                            }
                
                            switch ($job.NodeGroupOp)
                            {
                                "Intersect"
                                {
                                    $jobNodeGroupRequestedNodes += Intersect $jobNodeGroupNodes;
                                }
                                "Union"
                                {
                                    $jobNodeGroupRequestedNodes += Union $jobNodeGroupNodes;
                                }
                                "Uniform"
                                {
                                    $jobNodeGroupRequestedNodes += Uniform $jobNodeGroupNodes;
                                }
                                default { }
                            }
                        }
                        else # if job is not specified with any node group, consider it requesting all the nodes
                        {
                            $jobNodeGroupRequestedNodes += @($azureNodes | % { $_.NetBiosName });
                        }

                        $jobRequestedNodes = @()
                        if ($null -ne $job.RequestedNodes)
                        {
                            $jobRequestedNodes += $job.RequestedNodes.Split(',',[StringSplitOptions]::RemoveEmptyEntries);
                        }

                        if ($jobRequestedNodes.Count -eq 0)
                        {
                            $requestedNodes = $jobNodeGroupRequestedNodes;
                        }
                        else
                        {
                            $requestedNodes =  @(Intersect @($jobNodeGroupRequestedNodes, $jobRequestedNodes));
                        }

                        if ($requestedNodes.Count -ne 0)
                        {
                            # get queued tasks and calculate the weight
                            $numOfQueuedTasks = $job.QueuedTasksCount;
                            
                            $numOfQueuedTasksWithRequiredNodes = 0;
                            $numOfIrrelevantQueuedTasksWithRequiredNodes = 0;
                            
                            $activeTasks = @(Get-HpcTask -Job $job -State Queued,Running -ErrorAction SilentlyContinue | ? { $_.Type -ne 'NodePrep' -and $_.Type -ne 'NodeRelease' -and $_.SubTaskId -le 0 -and  ($_.Type -eq 'ParametricSweep' -or $_.state -eq 'Queued') });
                            
                            foreach ($task in $activeTasks)
                            {
                                $queuedTaskCount = 0
                                $taskRequireNode = 0
                                switch($task.UnitType)
                                {
                                    "Node" { $taskRequireNode += [math]::Max($task.MinNodes, 1/$NumOfActiveQueuedTasksPerNodeToGrow) }
                                    "Socket" { $taskRequireNode += [math]::Max($task.MinSockets/$SocketsPerNode, 1/$NumOfActiveQueuedTasksPerNodeToGrow) }
                                    "Core" { $taskRequireNode += [math]::Max($task.MinCores/$CoresPerNode, 1/$NumOfActiveQueuedTasksPerNodeToGrow) }
                                    default {}
                                }
                                    
                                switch ($task.Type)
                                {
                                    "Basic"
                                    {
                                        $queuedTaskCount = 1;
                                    }
                                    "ParametricSweep"
                                    {
                                        if($task.TotalSubTaskCount -gt 0)
                                        {
                                            $queuedTaskCount = $task.TotalSubTaskCount - @(Get-HpcTask -Job $job -ErrorAction SilentlyContinue | ? { $_.Id -eq $task.Id -and $_.SubTaskId -gt 0 -and $_.State -ne 'Queued' }).Count
                                        }
                                    }
                                    "Service"
                                    {
                                        $queuedTaskCount = 1;
                                    }
                                    default
                                    {
                                    }
                                }
                                
                                if ([string]::IsNullOrEmpty($task.RequiredNodes))
                                {
                                    $requiredNodeNumber += $queuedTaskCount*$taskRequireNode
                                }
                                else
                                {
                                    $requiredNodes = @($task.RequiredNodes.Split(',',[StringSplitOptions]::RemoveEmptyEntries));
                                    # Check if any required nodes are in the requested nodes
                                    # Add weights to the required nodes for the tasks within requested nodes
                                    $irrelevantTask = $true;
                                    foreach ($node in $requiredNodes)
                                    {
                                        if ($nodesNamed.ContainsKey($node))
                                        {
                                            $nodesNamed[$node].RequestedWeight += $queuedTaskCount; # each required nodes would add task count as weight
                                            $irrelevantTask = $false;
                                        }
                                    }
                                    if ($irrelevantTask)
                                    {
                                        $numOfIrrelevantQueuedTasksWithRequiredNodes += $queuedTaskCount
                                    }
                                    else
                                    {
                                        $requiredNodeNumber += $queuedTaskCount*$taskRequireNode
                                    }

                                    $numOfQueuedTasksWithRequiredNodes += $queuedTaskCount;
                                }
                            }
                
                            $totalNumOfRelevantQueuedTasks += $numOfQueuedTasks-$numOfIrrelevantQueuedTasksWithRequiredNodes;
                            $numOfQueuedTasksWithoutRequiredNodes = $numOfQueuedTasks - $numOfQueuedTasksWithRequiredNodes;

                            # Add weights to the requested nodes for the tasks without required nodes
                            if ($numOfQueuedTasksWithoutRequiredNodes -ne 0)
                            {
                                $weight = $numOfQueuedTasksWithoutRequiredNodes*1.0/$requestedNodes.Count
                                foreach ($node in $requestedNodes)
                                {
                                    $nodesNamed[$node].RequestedWeight += $weight;
                                }
                            }
                        }
                        else
                        {
                            $numOfIrrelevantJobs++;
                        }
                    } # end of foreach active jobs                    
                    
                    LogInfo "Number of active relevant queued tasks : $totalNumOfRelevantQueuedTasks"

                    # if the number of queued tasks exceeds the threshold
                    if ($totalNumOfRelevantQueuedTasks -gt $NumOfActiveQueuedTasksToGrowThreshold)
                    {
                        # calculate how many nodes to grow
                        $numOfNodesToGrow = [math]::Ceiling($requiredNodeNumber*(1+$ExtraNodesGrowRatio/100))
                        if ($numOfNodesToGrow -lt $NumOfInitialNodesToGrow -and $allNodesNotDeployedOrStopped)
                        {
                            $numOfNodesToGrow = $NumOfInitialNodesToGrow;
                        }

                        # check idle nodes for now
                        $idleAzureNodesToCheck = @($azureNodes | ? { $_.NodeState -eq 'Online' -and $_.HealthState -eq 'OK' })
                        $idleAzureNodes = @();
                        foreach ($node in $idleAzureNodesToCheck)
                        {
                            $jobCount = (Get-HpcJob -NodeName $node.NetBiosName -ErrorAction SilentlyContinue).Count;
                            if ($jobCount -eq 0)
                            {
                                $idleAzureNodes += $node.NetBiosName;
                            }
                        }

                        # sort the nodes by weight and choose the nodes
                        $azureNodesSorted = @($azureNodes | sort -Property @{Expression="RequestedWeight";Descending=$true},@{Expression="NodeState";Descending=$false} | ? { $_.NodeState -eq 'NotDeployed' -or $_.NodeState -eq 'Offline' -or $idleAzureNodes -ccontains $_.NetBiosName })
                        if ($numOfNodesToGrow -gt $azureNodesSorted.Count)
                        {
                            $numOfNodesToGrow = $azureNodesSorted.Count;
                        }

                        # choose the number of nodes with weight
                        $AllNodesNeededForQueuedJobTask = @($azureNodesSorted[0..($numOfNodesToGrow-1)] | ? {$_.RequestedWeight -gt 0.0})
                        $nodesToGrow = $AllNodesNeededForQueuedJobTask | ?{$_.NodeState -ne 'Online'}

                        # bring offline nodes if any
                        $nodesToGrowByBringOnline = @($nodesToGrow | ? {$_.NodeState -eq 'Offline' -and $_.HealthState -eq 'OK'})
                        if ($nodesToGrowByBringOnline.Count -gt 0)
                        {
                            LogInfo "Grow nodes by bringing online : $($nodesToGrowByBringOnline.Count)"
                            Set-HpcNodeState -Node $nodesToGrowByBringOnline -State online -ErrorAction SilentlyContinue | Out-Null
                            # check growingIaaSNodes list
                            $nodesToRemove = $growingIaaSNodes.keys |?{$nodesToGrowByBringOnline.NetBiosName -contains $_}
                            if($nodesToRemove.Count -gt 0)
                            {
                                foreach($nodeName in $nodesToRemove)
                                {
                                    $growingIaaSNodes.Remove($nodeName)
                                }
                            }

                            $nodesToGrow = @($nodesToGrow | ? {$nodesToGrowByBringOnline -notcontains $_})                            
                        }

                        LogInfo "Nodes to grow capacity : $($azureNodesSorted.Count-$nodesToGrowByBringOnline.Count)"
                        LogInfo "Nodes to grow for active relevant queued tasks : $($nodesToGrow.Count), required node number : $requiredNodeNumber"
                    }            
                }
            }
            else
            {
                LogWarning "There are no nodes in scope for grow and shrink. Please check the NodeType and NodeTemplates specified."
            }
        } # end check for numOfQueuedJobs and numOfActiveJobs

        # grow the nodes
        if ($nodesToGrow.Count -ne 0)
        {
            LogInfo "+++++++++++++++Grow Nodes++++++++++++++++++" 

            # for Azure Burst nodes
            if ($NodeType -eq $NodeTypes.AzureNodes)
            {
                # check if there are on-going starting/stopping operations on the node templates; if not, perform the start operation.
                $nodesHavingOperations = @()
                $nodesToAddForMissingRolesInInitialDeployment = @()
                $nodesToGrowTemplates =   @($nodesToGrow | % {$_.Template} | select -Unique)
                foreach ($nodeTemplate in $nodesToGrowTemplates)
                {
                    $nodes = $nodesTemplated[$nodeTemplate]
                    if ( @(Get-HpcOperation -Node $nodes -State Executing,Reverting -Name 'Starting Windows Azure Nodes','Stopping Windows Azure Nodes' -ErrorAction SilentlyContinue).Count -ne 0)
                    {
                        LogInfo "Node template '$nodeTemplate' is under deployment operations"
                        $nodesHavingOperations += $nodes;
                        continue;
                    }

                    # check if it is the initial deployment for the template; if yes, whether all role sizes are included; if not, add one node per each missing role size to make sure the deployment can be started
                    if ( @($nodes | ? { $_.NodeState -ne 'NotDeployed'}).Count -gt 0)
                    {
                        continue;
                    }

                    $roles = @($nodes | % { $_.AzureInstanceSize } | select -Unique)
                    if ($roles.Count -gt 1)
                    {
                        $nodesToGrowInTemplate = @($nodesToGrow | ? { $nodes.Contains($_) });
                        $rolesToGrowInTemplate = @($nodesToGrowInTemplate | % { $_.AzureInstanceSize } | select -Unique)
                        if ($rolesToGrowInTemplate.Count -ne $roles.Count)
                        {
                            $rolesMissing = @($roles | ? { -not $rolesToGrowInTemplate.Contains($_)})
                            foreach ($role in $rolesMissing)
                            {
                                    $nodesToAddForMissingRolesInInitialDeployment += @( $nodes | ? { $_.AzureInstanceSize -eq $role} | sort -Property RequestedWeight -Descending )[0]
                            }
                        }
                    }
                }
                
                $nodesToRemoveForOnGoingOperation = @()
                $temp = @()
                foreach ($node in $nodesToGrow)
                {
                    if ($nodesHavingOperations.Contains($node))
                    {
                        $nodesToRemoveForOnGoingOperation += $node
                    }
                    else
                    {
                        $temp += $node;
                    }
                }
                $nodesToGrow = $temp;
                
                if ($nodesToRemoveForOnGoingOperation.Count-ne 0)
                {
                    LogInfo "Remove $($nodesToRemoveForOnGoingOperation.Count) nodes for ongoing operations:"
                    PrintNodes $nodesToRemoveForOnGoingOperation
                }

                if ($nodesToAddForMissingRolesInInitialDeployment.Count -ne 0)
                {
                    LogInfo "Add $($nodesToAddForMissingRolesInInitialDeployment.Count) nodes for initial deployment startup:"
                    PrintNodes $nodesToAddForMissingRolesInInitialDeployment
                }

                $nodesToGrow += $nodesToAddForMissingRolesInInitialDeployment
            }
            elseif ($NodeType -eq $NodeTypes.ComputeNodes) # for Azure IaaS VMs there is no need for such validations
            {
            }
            
            if ($nodesToGrow.Count -ne 0)
            {
                if ($NodeType -eq $NodeTypes.AzureNodes)
                {
                    LogInfo "Growing the $($nodesToGrow.Count) node(s):"
                    PrintNodes $nodesToGrow

                    # use sync start here
                    $startAzureNodesScript= {
                        Param ([String[]]$Nodes)
                        Add-PSSnapin microsoft.hpc
                        $error.Clear();
                        Start-HpcAzureNode -Name $Nodes -Async $false -ErrorAction SilentlyContinue
                        $nodesGrowSucceeded = $?
                        if ($error.Count -ne 0)
                        {
                            $error
                        }
                        $nodesGrowSucceeded
                    };

                    StartNodes $startAzureNodesScript @($nodesToGrow | % {$_.NetBiosName}) 60                                                
                }
                elseif ($NodeType -eq $NodeTypes.ComputeNodes)
                {
                    $Nodes = @()
                    # check whether the nodes is already in $growingIaaSNodes
                    foreach($node in $nodesToGrow)
                    {
                        if($growingIaaSNodes.Keys -notcontains $node.NetBiosName)
                        {
                            $Nodes += $node.NetBiosName                             
                        }
                    }

                    # async start, need to bring the nodes online                    
                    if($Nodes.Count -gt 0)
                    {
                        
                        try
                        {
                            LogInfo "Bring online nodes before growing: $($Nodes -join ',')"
                            Set-HpcNodeState -Name $Nodes -State online -ErrorAction SilentlyContinue | Out-Null
                            LogInfo "Growing the $($Nodes.Count) node(s): $($Nodes -join ',')"
                            & $env:CCP_HOME\bin\Start-HpcIaaSNode.ps1 -Name $Nodes -ErrorAction Stop
                        }
                        catch
                        {
                            LogError "Start Azure VMs failed: $_"
                        }
                    }
                    
                    foreach($nodeName in $Nodes)
                    {
                        $growingIaaSNodes[$nodeName] = Get-Date
                    }
                   
                }
            }
        }
        else
        {
            if ($NumOfQueuedJobsPerNodeToGrow -eq 0 -and $NumOfActiveQueuedTasksPerNodeToGrow -eq 0)
            {
                LogInfo "Grow nodes is not enabled."
            }
            else
            {
                LogInfo "No enough relevant workload or nodes to grow."
            }
        }

        if ($NodeType -eq $NodeTypes.ComputeNodes -and $growingIaaSNodes.Keys.Count -gt 0)
        {
            # check growing nodes, if health is OK, remove from growingIaaSNodes list, if not and timeout (20 minutes), stop it and remove from growingIaaSNodes list
            $Nodes = Get-HpcNode -Name @($growingIaaSNodes.Keys) -ErrorAction SilentlyContinue
            $okNodes = @($Nodes|?{$_.HealthState -eq "OK"} |%{$_.NetBiosName})
            if($okNodes.Count -gt 0)
            {
                LogInfo "Bring online nodes: $($okNodes -join ',')"
                Set-HpcNodeState -Name $okNodes -State online -ErrorAction SilentlyContinue | Out-Null
            }
            
            $newNodesList = @{}
            $timeoutNodes = @{}
            $end = Get-Date
            foreach($nodeName in $growingIaaSNodes.Keys)
            {
                if($okNodes -notcontains $nodeName)
                {
                    $start = $growingIaaSNodes[$nodeName]                            
                    $span = $end - $start
                    if($span.TotalMinutes -gt 20)
                    {
                        $timeoutNodes[$nodeName] = $growingIaaSNodes[$nodeName]
                    }
                    else
                    {
                        $newNodesList[$nodeName] = $growingIaaSNodes[$nodeName]
                    }
                }
            }
            
            $growingIaaSNodes = $newNodesList        
            if($timeoutNodes.Count -gt 0)
            {
                LogInfo "Stopping timeout nodes: $($timeoutNodes.Keys -join ',')"
                try
                {
                    & $env:CCP_HOME\bin\Stop-HpcIaaSNode.ps1 -Name $timeoutNodes.Keys -ErrorAction Stop
                }
                catch
                {
                    LogError "Stop Azure VMs failed: $_"
                    $growingIaaSNodes += $timeoutNodes
                }
            }            
        }
    }
    
    # calculate and shrink the resource    
    if ($checkToShrink)
    {
        LogInfo "===============Shrink Check================" 
        $lastCheckToShrink = Get-Date;
        $azureNodes = @();
        if ($NodeTemplates.Count -ne 0)
        {
            $azureNodes = @(Get-HpcNode -GroupName $NodeType -TemplateName $NodeTemplates -ErrorAction SilentlyContinue)
        }
        else
        {
            $azureNodes = @(Get-HpcNode -GroupName $NodeType -ErrorAction SilentlyContinue)
        }

        # remove head node if in the list
        if ($NodeType -eq $NodeTypes.ComputeNodes)
        {
            $azureNodes = @($azureNodes | ? { -not $_.IsHeadNode })
        }
        
        $nodesNamed = @{};
        $nodesTemplated = @{};
            
        foreach ($node in $azureNodes)
        {
            Add-Member -InputObject $node -MemberType NoteProperty -Name 'RequestedWeight' -Value 0.0;

            $nodesNamed[$node.NetBiosName] = $node;
            if ($nodesTemplated.ContainsKey($node.Template))
            {
                $nodesTemplated[$node.Template] += $node;
            }
            else
            {
                $nodesTemplated[$node.Template] = @($node);
            }
        }

        # check online and offline nodes
        $idleAzureNodesToCheck = @($azureNodes | ? { $_.NodeState -eq 'Online' })
        $nodesToShrink = @();
        
        # check idle nodes for now
        $idleAzureNodes = @();
        foreach ($node in $idleAzureNodesToCheck)
        {
            $jobCount = (Get-HpcJob -NodeName $node.NetBiosName -ErrorAction SilentlyContinue).Count;
            if ($jobCount -eq 0)
            {
                $idleAzureNodes += $node.NetBiosName;
            }
        }

        # add offline nodes
        if ($NodeType -eq $NodeTypes.AzureNodes)
        {
            $idleAzureNodes += @($azureNodes | ? { $_.NodeState -eq 'Offline' } | % { $_.NetBiosName })
        }
        else
        {
            $idleAzureNodes += @($azureNodes | ? { $_.NodeState -eq 'Offline' -and $_.HealthState -eq 'OK' } | % { $_.NetBiosName })
        }

        if ($idleAzureNodes.Count -ne 0)
        {
            LogInfo "$($idleAzureNodes.Count) idle node(s) found in this check: $idleAzureNodes"
        }
        $idleNodesHistory+=,$idleAzureNodes

        if ($idleNodesHistory.Count -ge $ShrinkCheckIdleTimes)
        {
            if ($idleNodesHistory.Count -gt $ShrinkCheckIdleTimes)
            {
                $temp = @();
                1..$ShrinkCheckIdleTimes | % { $temp+=, $idleNodesHistory[$_] }
                $idleNodesHistory = $temp;
            }
        
            $nodesToShrinkNames = @(Intersect $idleNodesHistory)
            $nodesToShrink = @()
            if ($nodesToShrinkNames.Count -gt 0)
            {
                $neededNodes = $AllNodesNeededForQueuedJobTask | %{$_.NetBiosName}
                $nodesToShrinkNames = $nodesToShrinkNames| ?{ $neededNodes -notcontains $_ }
                if($nodesToShrinkNames.Count -gt 0)
                {
                    $nodesToShrink =  @( $nodesToShrinkNames | % { $nodesNamed[$_] } )
                }
            }

            if ($nodesToShrink.Count -gt 0)
            {
                LogInfo "---------------Shrink Nodes----------------"            
                LogInfo "Idle nodes to shrink : $($nodesToShrink.Count)"
                PrintNodes $nodesToShrink

                # Shrink the nodes
                # check if there are on-going starting/stopping operations on the node template; if not, perform the shrink operation.
                $nodesShrinkSucceeded = $false;
                if ($NodeType -eq $NodeTypes.AzureNodes)
                {
                    $nodesHavingOperations = @()
                    $nodesToRetainPerRoleIfNotDeploymentShutdown = @()
                    $nodesToShrinkTemplates = @($nodesToShrink | % { $_.Template } | select -Unique)
                    foreach ($nodeTemplate in $nodesToShrinkTemplates)
                    {
                        $nodes = $nodesTemplated[$nodeTemplate]
                        if ( @(Get-HpcOperation -Node $nodes -State Executing,Reverting -Name 'Starting Windows Azure Nodes','Stopping Windows Azure Nodes' -ErrorAction SilentlyContinue).Count -ne 0)
                        {
                            LogInfo "Node template $($nodeTemplate) is under deployment operations"
                            $nodesHavingOperations += $nodes;
                            continue;
                        }

                        $nodesToShrinkInTemplate = @($nodesToShrink | ? { $nodes.Contains($_) })
                        
                        # if shutting down the whole deployment
                        if ( @($nodes | ? { (-not $nodesToShrinkInTemplate.Contains($_)) -and $_.NodeState -ne 'NotDeployed'}).Count -eq 0)
                        {
                            continue;
                        }
                        # retain one instance per role if not shutting down the whole deployment for the template
                        $roles = @($nodes | % { $_.AzureInstanceSize } | select -Unique)
                        if ($roles.Count -gt 1)
                        {
                            $rolesToShrinkInTemplate = @($nodesToShrinkInTemplate | % { $_.AzureInstanceSize } | select -Unique)
                            foreach ($role in $rolesToShrinkInTemplate)
                            {
                                $nodesInRole = @($nodes | ? { $_.AzureInstanceSize -eq $role})
                                # if all the nodes in this role would be shutdown
                                if (@($nodesInRole | ? { (-not $nodesToShrinkInTemplate.Contains($_)) -and $_.NodeState -ne 'NotDeployed'}).Count -eq 0)
                                {
                                    $nodesToRetainPerRoleIfNotDeploymentShutdown +=  @($nodesToShrinkInTemplate | ? {$_.AzureInstanceSize -eq $role})[0]
                                }
                            }
                        }
                    }                    
                    
                    $nodesToRemoveForOnGoingOperation = @()
                    $nodesToRemoveForSingleInstancePerRole = @()
                    $temp = @()
                    foreach ($node in $nodesToShrink)
                    {
                        if ($nodesHavingOperations.Contains($node))
                        {
                            $nodesToRemoveForOnGoingOperation += $node;
                        }
                        elseif ($nodesToRetainPerRoleIfNotDeploymentShutdown.Contains($node))
                        {
                            $nodesToRemoveForSingleInstancePerRole += $node;
                        }
                        else
                        {
                            $temp += $node;
                        }
                    }
                    $nodesToShrink = $temp;
                
                    if ($nodesToRemoveForOnGoingOperation.Count-ne 0)
                    {
                        LogInfo "Remove $($nodesToRemoveForOnGoingOperation.Count) nodes from the shrink list for ongoing operations:"
                        PrintNodes $nodesToRemoveForOnGoingOperation
                    }

                    if ($nodesToRemoveForSingleInstancePerRole.Count-ne 0)
                    {
                        LogInfo "Remove $($nodesToRemoveForSingleInstancePerRole.Count) nodes from the shrink list for single instance per role:"
                        PrintNodes $nodesToRemoveForSingleInstancePerRole
                    }

                    if ($nodesToShrink.Count -gt 0)
                    {
                        LogInfo "Shrinking the $($nodesToShrink.Count) Azure nodes"
                        PrintNodes $nodesToShrink
                        LogInfo "Bringing nodes offline"
                        Set-HpcNodeState -Node $nodesToShrink -State offline -WarningAction Ignore -ErrorAction SilentlyContinue | Out-Null
            
                        $error.Clear();
                        Stop-HpcAzureNode -Node $nodesToShrink -Force $false -Async $true -ErrorAction SilentlyContinue
                        if (-not $?)
                        {
                            LogError "Stop Azure nodes failed."
                            LogError $error
                        }
                        else
                        {
                            $nodesShrinkSucceeded = $true;
                        }
                    }
                    else
                    {
                        LogInfo "No Azure burst nodes to shrink"
                    }           
                }
                elseif ($NodeType -eq $NodeTypes.ComputeNodes) 
                {
                    LogInfo "Bringing nodes offline"
                    Set-HpcNodeState -Node $nodesToShrink -State offline -WarningAction Ignore -ErrorAction SilentlyContinue | Out-Null
                    
                    try
                    {
                        & $env:CCP_HOME\bin\Stop-HpcIaaSNode.ps1 -Node $nodesToShrink -ErrorAction Stop                    
                        $nodesShrinkSucceeded = $true;
                    }
                    catch
                    {
                        LogError "Stop Azure VMs failed: $_"
                    }
                    
                    # check growingIaaSNodes list
                    $nodesToRemove = $growingIaaSNodes.keys |?{$nodesToShrink.NetBiosName -contains $_}
                    if($nodesToRemove.Count -gt 0)
                    {
                        foreach($nodeName in $nodesToRemove)
                        {
                            $growingIaaSNodes.Remove($nodeName)
                        }
                    }                           
                }

                if ($nodesShrinkSucceeded)
                {
                    LogInfo "Nodes shrink operation started successfully."
                    $temp = @();
                    foreach($historyItem in $idleNodesHistory)
                    {
                        $temp +=, ($historyItem | ?{$nodesToShrinkNames -notcontains $_})
                    }

                    $idleNodesHistory = $temp;
                }
            }
            else
            {
                LogInfo "No idle nodes to shrink"
            }
        }
    }
    
    WaitScroll 10
}

# SIG # Begin signature block
# MIIdgwYJKoZIhvcNAQcCoIIddDCCHXACAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU4eRKe6ZIgSriZ9YAq+63It9b
# U2OgghhfMIIE2jCCA8KgAwIBAgITMwAAATooqWKENAQ6aAAAAAABOjANBgkqhkiG
# 9w0BAQUFADB3MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEw
# HwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EwHhcNMTkxMDIzMjMxNzEx
# WhcNMjEwMTIxMjMxNzExWjCByjELMAkGA1UEBhMCVVMxCzAJBgNVBAgTAldBMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# LTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEm
# MCQGA1UECxMdVGhhbGVzIFRTUyBFU046QUI0MS00QjI3LUYwMjYxJTAjBgNVBAMT
# HE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggEiMA0GCSqGSIb3DQEBAQUA
# A4IBDwAwggEKAoIBAQD4sio6vNOH8bDBok2LoiN4D73CYRK6DEo/NwIA1CHxN8Mg
# 67v4GW2Gg3o0lik5j5OKmWkGav1NN3Cvy6guDuvdsswW1MSAIH8HZhjYld0AgSYY
# YTtfbjerKfnCeHYz8yuS2M0rhwxhzPUp9zh1OW6KSw1Pq+NOhDc8/7kYyps3I2Vr
# T/JEshi/mrE33XHn/2QfA19MN+OxUjmPySL1OO4S5GFvDjErxZAz5XrrQMMX65/l
# GvdQw6f5hu8KuKix8RQ9gbaBIU680s40eNx5AOTLkp5weN4YpIY+IxMXp41sUfCb
# qJcoz6UlI2Nyl19mUo3wbnwQGkTdEgD6HW/tC7qRAgMBAAGjggEJMIIBBTAdBgNV
# HQ4EFgQUwE/e9+gnSO9OeN9eOgsjg8cAy9cwHwYDVR0jBBgwFoAUIzT42VJGcArt
# QPt2+7MrsMM1sw8wVAYDVR0fBE0wSzBJoEegRYZDaHR0cDovL2NybC5taWNyb3Nv
# ZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljcm9zb2Z0VGltZVN0YW1wUENBLmNy
# bDBYBggrBgEFBQcBAQRMMEowSAYIKwYBBQUHMAKGPGh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2kvY2VydHMvTWljcm9zb2Z0VGltZVN0YW1wUENBLmNydDATBgNV
# HSUEDDAKBggrBgEFBQcDCDANBgkqhkiG9w0BAQUFAAOCAQEAcfwWy/jkHd+5oHBh
# hosLBNq6tbMxeoL1zEl9LnrKgc8CT0PSq1dfueehYbXOhpRgGwR2JRqm8FzBUbKq
# vhFOKekbiajTwpcQmPYdQ/lUBSXXw2vMdvj8Qzon+quHlqISLUMG/DrZN+qoxQmO
# X6vOMjIXaa43p2+d7OycYYcq+5S+slpRufgu2ghNKdUD5GGiuXRIaqSAghxtgfWS
# +6fBK2+PUlbcozYAvCT+lbnatIy7ZBrIlD3CHlGFMk37Ng7mmCkJYLylifuqxHQr
# 7vR7jQmC8ykHBYrz95JE4nz24OPDe8MwKZbOp1ek40plnok8sw2u2xPsfQeOYLPY
# kOJsNjCCBfQwggPcoAMCAQICEzMAAAGGTSF1oNkHviwAAAAAAYYwDQYJKoZIhvcN
# AQELBQAwfjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYG
# A1UEAxMfTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMTAeFw0yMDAzMDQx
# ODM5NDZaFw0yMTAzMDMxODM5NDZaMHQxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xHjAcBgNVBAMTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjCCASIw
# DQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALj17LJpqJ6Dddvt7D7+EDfiCrNG
# 5F5v2y8EXo3f6IsPkDSIx1226eeZsVVD6U1amF//E4Z5/m9cwwyTvji3Gj+RPoIq
# rQbNX4iECoPK2MfdSAaEsE1n9Ra5A+CueHBp9DdlyWxejWW2jinKmzj5fdHJB+fE
# LCq2NHGMJD4DAjOTS9JUWch3oDBsHvfDaUn4wL4TqdWbK+KSnsNPazBMXTkmR8xS
# 3MOiyS3P+m+8xZjUhQ5nvVepZRdzB/NYMn73pbEEfoukNDV8JDc84DeMIG7eYyIH
# WRKwyKEf56rUTMPQSzuIhPUyUoRE9CYL7GUr72k8DDqP6s/aC5h8qswWvf0CAwEA
# AaOCAXMwggFvMB8GA1UdJQQYMBYGCisGAQQBgjdMCAEGCCsGAQUFBwMDMB0GA1Ud
# DgQWBBSFMVMUe4JpQJ1OBleNr84BD3E6bjBFBgNVHREEPjA8pDowODEeMBwGA1UE
# CxMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMRYwFAYDVQQFEw0yMzAwMTIrNDU4Mzg0
# MB8GA1UdIwQYMBaAFEhuZOVQBdOCqhc3NyK1bajKdQKVMFQGA1UdHwRNMEswSaBH
# oEWGQ2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY0NvZFNp
# Z1BDQTIwMTFfMjAxMS0wNy0wOC5jcmwwYQYIKwYBBQUHAQEEVTBTMFEGCCsGAQUF
# BzAChkVodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY0Nv
# ZFNpZ1BDQTIwMTFfMjAxMS0wNy0wOC5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG
# 9w0BAQsFAAOCAgEAQOQtdYoO0nysuHd3tc/XFTWzoa3SMOp4egilO+exES30ywqu
# JUYp1VUZImjDUvP371sg2Y9mjtl0yE2FYZBCcQXvP/dzOHQws7TPjxzEKuMtyHQ/
# azG+1xpPnssGYTL61uGVQHqLPvYpZq/G6E/nPEoQKG0unyAeSnn/VhM+W9FgWtmv
# +K6naPNz86jk3j+r7KE6xFPcom7rZ6RBRQ+w9TZtaxoX+FQ9b8vY7UV5x/7o44kt
# PZsdoDOv4QECfQoBSLB0z4BS9qwb2Qctf4hdeURm9+xcbPPEWVbM1ukz326ZZYxA
# 9MZk+lIJMMOz/UKLQGvb+hdyBrJgtpkJayPWb9rRXw4dkZumk/VGsF4tAp8BOO0C
# XTGuEyviSB+8nqe0KGD13HLgOIZaeyP/9DLBSzVTFVyFFHt4Vo/czz8FXR54yi1f
# BM0jDNJ3e4DMAj41Ks3mlWVB4LRddO554O7ENyHdLlRR0M692U52VEBr7zlKLoeY
# RSDHePRhhILVFYF0SHCwB0fqde1cSyEADF/w9aHbAKxzMx78Xi9ODhyYOwFNnDCs
# eovmStf76zrWwtYDrtifgNvqtdX0iZx/lQwKrT3AmPkf3cof2pzXIKInMMK1u2DI
# dhcCRIdA2miPu0NfqSj2ATy9epkgaPzabANMBj2h9EfRFIwsmqmAusE8Io0wggYH
# MIID76ADAgECAgphFmg0AAAAAAAcMA0GCSqGSIb3DQEBBQUAMF8xEzARBgoJkiaJ
# k/IsZAEZFgNjb20xGTAXBgoJkiaJk/IsZAEZFgltaWNyb3NvZnQxLTArBgNVBAMT
# JE1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eTAeFw0wNzA0MDMx
# MjUzMDlaFw0yMTA0MDMxMzAzMDlaMHcxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xITAfBgNVBAMTGE1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQTCC
# ASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJ+hbLHf20iSKnxrLhnhveLj
# xZlRI1Ctzt0YTiQP7tGn0UytdDAgEesH1VSVFUmUG0KSrphcMCbaAGvoe73siQcP
# 9w4EmPCJzB/LMySHnfL0Zxws/HvniB3q506jocEjU8qN+kXPCdBer9CwQgSi+aZs
# k2fXKNxGU7CG0OUoRi4nrIZPVVIM5AMs+2qQkDBuh/NZMJ36ftaXs+ghl3740hPz
# CLdTbVK0RZCfSABKR2YRJylmqJfk0waBSqL5hKcRRxQJgp+E7VV4/gGaHVAIhQAQ
# MEbtt94jRrvELVSfrx54QTF3zJvfO4OToWECtR0Nsfz3m7IBziJLVP/5BcPCIAsC
# AwEAAaOCAaswggGnMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFCM0+NlSRnAK
# 7UD7dvuzK7DDNbMPMAsGA1UdDwQEAwIBhjAQBgkrBgEEAYI3FQEEAwIBADCBmAYD
# VR0jBIGQMIGNgBQOrIJgQFYnl+UlE/wq4QpTlVnkpKFjpGEwXzETMBEGCgmSJomT
# 8ixkARkWA2NvbTEZMBcGCgmSJomT8ixkARkWCW1pY3Jvc29mdDEtMCsGA1UEAxMk
# TWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5ghB5rRahSqClrUxz
# WPQHEy5lMFAGA1UdHwRJMEcwRaBDoEGGP2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNv
# bS9wa2kvY3JsL3Byb2R1Y3RzL21pY3Jvc29mdHJvb3RjZXJ0LmNybDBUBggrBgEF
# BQcBAQRIMEYwRAYIKwYBBQUHMAKGOGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
# a2kvY2VydHMvTWljcm9zb2Z0Um9vdENlcnQuY3J0MBMGA1UdJQQMMAoGCCsGAQUF
# BwMIMA0GCSqGSIb3DQEBBQUAA4ICAQAQl4rDXANENt3ptK132855UU0BsS50cVtt
# DBOrzr57j7gu1BKijG1iuFcCy04gE1CZ3XpA4le7r1iaHOEdAYasu3jyi9DsOwHu
# 4r6PCgXIjUji8FMV3U+rkuTnjWrVgMHmlPIGL4UD6ZEqJCJw+/b85HiZLg33B+Jw
# vBhOnY5rCnKVuKE5nGctxVEO6mJcPxaYiyA/4gcaMvnMMUp2MT0rcgvI6nA9/4UK
# E9/CCmGO8Ne4F+tOi3/FNSteo7/rvH0LQnvUU3Ih7jDKu3hlXFsBFwoUDtLaFJj1
# PLlmWLMtL+f5hYbMUVbonXCUbKw5TNT2eb+qGHpiKe+imyk0BncaYsk9Hm0fgvAL
# xyy7z0Oz5fnsfbXjpKh0NbhOxXEjEiZ2CzxSjHFaRkMUvLOzsE1nyJ9C/4B5IYCe
# FTBm6EISXhrIniIh0EPpK+m79EjMLNTYMoBMJipIJF9a6lbvpt6Znco6b72BJ3QG
# Ee52Ib+bgsEnVLaxaj2JoXZhtG6hE6a/qkfwEm/9ijJssv7fUciMI8lmvZ0dhxJk
# Aj0tr1mPuOQh5bWwymO0eFQF1EEuUKyUsKV4q7OglnUa2ZKHE3UiLzKoCG6gW4wl
# v6DvhMoh1useT8ma7kng9wFlb4kLfchpyOZu6qeXzjEp/w7FW1zYTRuh2Povnj8u
# VRZryROj/TCCB3owggVioAMCAQICCmEOkNIAAAAAAAMwDQYJKoZIhvcNAQELBQAw
# gYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMT
# KU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDExMB4XDTEx
# MDcwODIwNTkwOVoXDTI2MDcwODIxMDkwOVowfjELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9zb2Z0IENvZGUgU2lnbmlu
# ZyBQQ0EgMjAxMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAKvw+nIQ
# HC6t2G6qghBNNLrytlghn0IbKmvpWlCquAY4GgRJun/DDB7dN2vGEtgL8DjCmQaw
# yDnVARQxQtOJDXlkh36UYCRsr55JnOloXtLfm1OyCizDr9mpK656Ca/XllnKYBoF
# 6WZ26DJSJhIv56sIUM+zRLdd2MQuA3WraPPLbfM6XKEW9Ea64DhkrG5kNXimoGMP
# LdNAk/jj3gcN1Vx5pUkp5w2+oBN3vpQ97/vjK1oQH01WKKJ6cuASOrdJXtjt7UOR
# g9l7snuGG9k+sYxd6IlPhBryoS9Z5JA7La4zWMW3Pv4y07MDPbGyr5I4ftKdgCz1
# TlaRITUlwzluZH9TupwPrRkjhMv0ugOGjfdf8NBSv4yUh7zAIXQlXxgotswnKDgl
# mDlKNs98sZKuHCOnqWbsYR9q4ShJnV+I4iVd0yFLPlLEtVc/JAPw0XpbL9Uj43Bd
# D1FGd7P4AOG8rAKCX9vAFbO9G9RVS+c5oQ/pI0m8GLhEfEXkwcNyeuBy5yTfv0aZ
# xe/CHFfbg43sTUkwp6uO3+xbn6/83bBm4sGXgXvt1u1L50kppxMopqd9Z4DmimJ4
# X7IvhNdXnFy/dygo8e1twyiPLI9AN0/B4YVEicQJTMXUpUMvdJX3bvh4IFgsE11g
# lZo+TzOE2rCIF96eTvSWsLxGoGyY0uDWiIwLAgMBAAGjggHtMIIB6TAQBgkrBgEE
# AYI3FQEEAwIBADAdBgNVHQ4EFgQUSG5k5VAF04KqFzc3IrVtqMp1ApUwGQYJKwYB
# BAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMB
# Af8wHwYDVR0jBBgwFoAUci06AjGQQ7kUBU7h6qfHMdEjiTQwWgYDVR0fBFMwUTBP
# oE2gS4ZJaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMv
# TWljUm9vQ2VyQXV0MjAxMV8yMDExXzAzXzIyLmNybDBeBggrBgEFBQcBAQRSMFAw
# TgYIKwYBBQUHMAKGQmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMv
# TWljUm9vQ2VyQXV0MjAxMV8yMDExXzAzXzIyLmNydDCBnwYDVR0gBIGXMIGUMIGR
# BgkrBgEEAYI3LgMwgYMwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvZG9jcy9wcmltYXJ5Y3BzLmh0bTBABggrBgEFBQcCAjA0HjIg
# HQBMAGUAZwBhAGwAXwBwAG8AbABpAGMAeQBfAHMAdABhAHQAZQBtAGUAbgB0AC4g
# HTANBgkqhkiG9w0BAQsFAAOCAgEAZ/KGpZjgVHkaLtPYdGcimwuWEeFjkplCln3S
# eQyQwWVfLiw++MNy0W2D/r4/6ArKO79HqaPzadtjvyI1pZddZYSQfYtGUFXYDJJ8
# 0hpLHPM8QotS0LD9a+M+By4pm+Y9G6XUtR13lDni6WTJRD14eiPzE32mkHSDjfTL
# JgJGKsKKELukqQUMm+1o+mgulaAqPyprWEljHwlpblqYluSD9MCP80Yr3vw70L01
# 724lruWvJ+3Q3fMOr5kol5hNDj0L8giJ1h/DMhji8MUtzluetEk5CsYKwsatruWy
# 2dsViFFFWDgycScaf7H0J/jeLDogaZiyWYlobm+nt3TDQAUGpgEqKD6CPxNNZgvA
# s0314Y9/HG8VfUWnduVAKmWjw11SYobDHWM2l4bf2vP48hahmifhzaWX0O5dY0Hj
# Wwechz4GdwbRBrF1HxS+YWG18NzGGwS+30HHDiju3mUv7Jf2oVyW2ADWoUa9WfOX
# pQlLSBCZgB/QACnFsZulP0V3HjXG0qKin3p6IvpIlR+r+0cjgPWe+L9rt0uX4ut1
# eBrs6jeZeRhL/9azI2h15q/6/IvrC4DqaTuv/DDtBEyO3991bWORPdGdVk5Pv4BX
# IqF4ETIheu9BCrE/+6jMpF3BoYibV3FWTkhFwELJm3ZbCoBIa/15n8G9bW1qyVJz
# Ew16UM0xggSOMIIEigIBATCBlTB+MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQSAy
# MDExAhMzAAABhk0hdaDZB74sAAAAAAGGMAkGBSsOAwIaBQCggaIwGQYJKoZIhvcN
# AQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUw
# IwYJKoZIhvcNAQkEMRYEFCWXoHhccjg3T5EbqUPsZgIGg01WMEIGCisGAQQBgjcC
# AQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAi5E/5GW8kAZLHwxVajqVLhEK9VNK
# ghRQlZh3fq7tp5svVGNg9NmlCRVZVQ+/ECeg337jAFE7Vz3xcHra41v1yOsuKwN0
# MwSg6rO5Sv82dIJ0SJ4Ma1rBy2v+C4QXL73VpVwoQc5aR8JcVmOPkyPP8m40Rk7i
# FDTcuR9vL1u7zByMW5QZMDOFnrAkP6wytDgzLVf1CK9TwVQO6u4Ec8H5VR3/YQdV
# S6R2EywORYD7OOjx/anC6ygaMMfiO4+vIV0KUCHwzqr+GIgF/N9638d//ER3uDkQ
# GUbsnLfDNYk6ED9Rgt9piJR71frTEZW036fpmRJBRswwQH/aAB/0BilREaGCAigw
# ggIkBgkqhkiG9w0BCQYxggIVMIICEQIBATCBjjB3MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSEwHwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0ECEzMAAAE6KKlihDQEOmgAAAAAATowCQYFKw4DAhoFAKBdMBgGCSqGSIb3
# DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIwMDYwNzEyMzM0N1ow
# IwYJKoZIhvcNAQkEMRYEFNdQh/RYjuZDNSI0N5ZAT7jN+OKWMA0GCSqGSIb3DQEB
# BQUABIIBAH9fXQ3Hx+M1+fnB4A4bLM2mmbQq7tRNTAaD67UXeFg4SnNpYb/85avc
# X9CwYYTl6VyPXowxi9Qd16FsQwZqoViVkxjZlVLqQpr1ag6C7RKx50S2/OrQ3VE3
# pfnagOdDEAtXhzOCqnQZ8IhKQMT+MGhQUDyJdiWUA0V5Ivd3PR6NsmlRCk9PQsB0
# Pasb7D8X00SRzIjikKAfRDd1wQQo2Cta/Q266/gBFtEPlWy0Pj+qAKiG7nnKxEXl
# E+lKix6ugiIl9UyfRAcjQkLN+yxUzFK5jm8LyAFxvFM7oifiWY9y2g9exjkSRddD
# pWoGvElrqrsPGK0g25LI2iLj2ipKKJ4=
# SIG # End signature block
