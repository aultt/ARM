configuration FCISQLServer
{
    param
    (
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$SQLServicecreds,
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$AgtServicecreds,
        [string]$imageoffer,
        [string]$SQLFeatures,
        [string]$SQLInstanceName,
        [string]$datadriveLetter,
        [string]$datadrivelabel,
        [string]$datadriveSize,
        [string]$logdriveLetter,
        [string]$logdrivelabel,
        [string]$logdriveSize,
        [string]$tempdbdriveLetter,
        [string]$tempdbdrivelabel,
        [string]$tempdbdriveSize,
        [string]$SQLSysAdmins,
        [string]$SourcePath,
        [Parameter(Mandatory)]
        [string]$ClusterName,
        [Parameter(Mandatory)]
        [string]$ClusterStaticIP,
        [Parameter(Mandatory)]
        [string]$ClusterIPSubnetClass,
        [Parameter(Mandatory)]
        [string]$ClusterIPSubnetMask,
        [Parameter(Mandatory)]
        [string]$FirstNode,
        [Parameter(Mandatory)]
        [string]$SQLClusterName,
        [Parameter(Mandatory)]
        [string]$SQLStaticIP,
        [string]$SQLPort=1433,
        [Parameter(Mandatory)]
        [string]$CloudWitnessName,
        [string]$TimeZone,
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$CloudWitnessKey, 

        [Int]$RetryCount = 20,
        [Int]$RetryIntervalSec = 30

    )

    Import-DscResource -ModuleName ComputerManagementdsc,sqlserverdsc,xFailOverCluster,xPendingReboot,Storagedsc,SecurityPolicydsc

    $ClusterIPandSubNetClass = $ClusterStaticIP + '/' +$ClusterIPSubnetClass
    $SQLVersion = $imageoffer.Substring(5,2)
    $SQLLocation = "MSSQL$(switch ($SQLVersion){17 {14} 16 {13}})"

    WaitForSqlSetup

    Node localhost
    {
        LocalConfigurationManager 
        {
            RebootNodeIfNeeded = $true
            ActionAfterReboot = 'ContinueConfiguration'
        }
        
        Script  FireWallRuleforSQLProbe
        {
            GetScript = {
                            $test = Get-NetFirewallRule -DisplayName "Load Balancer SQL Probe" -ErrorAction SilentlyContinue
                            if ($test)
                            {return @{ 'Result' = $test}}
                            else
                            {return @{ 'Result' = "No Rule Present"} }
                        }
            SetScript = {New-NetFirewallRule -DisplayName "Load Balancer SQL Probe" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 59999}
            TestScript = { 
                            $test = Get-NetFirewallRule -DisplayName "Load Balancer SQL Probe" -ErrorAction SilentlyContinue
                            if ($test)
                            {return $true}
                            else
                            {return $false}
                         }
            PsDscRunAsCredential = $AdminCreds
        }
        
        Script  FireWallRuleforClusterProbe
        {
            GetScript = {
                            $test = Get-NetFirewallRule -DisplayName "Load Balancer Cluster Probe" -ErrorAction SilentlyContinue
                            if ($test)
                            {return @{ 'Result' = $test}}
                            else
                            {return @{ 'Result' = "No Rule Present"} }
                        }
            SetScript = {New-NetFirewallRule -DisplayName "Load Balancer Cluster Probe" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 58888}
            TestScript = { 
                            $test = Get-NetFirewallRule -DisplayName "Load Balancer Cluster Probe" -ErrorAction SilentlyContinue
                            if ($test)
                            {return $true}
                            else
                            {return $false}
                         }      
            PsDscRunAsCredential = $AdminCreds
        }

        WindowsFeature AddFailoverFeature
        {
            Ensure = 'Present'
            Name   = 'Failover-clustering'
        }

		WindowsFeature FailoverClusterTools 
        { 
            Ensure = "Present" 
            Name = "RSAT-Clustering-Mgmt"
			DependsOn = "[WindowsFeature]AddFailoverFeature"
        }
        
        WindowsFeature AddRemoteServerAdministrationToolsClusteringPowerShellFeature
        {
            Ensure    = 'Present'
            Name      = 'RSAT-Clustering-PowerShell'
            DependsOn = '[WindowsFeature]AddFailoverFeature'
        }

        WindowsFeature AddRemoteServerAdministrationToolsClusteringCmdInterfaceFeature
        {
            Ensure    = 'Present'
            Name      = 'RSAT-Clustering-CmdInterface'
            DependsOn = '[WindowsFeature]AddRemoteServerAdministrationToolsClusteringPowerShellFeature'
        }

        WindowsFeature ADPS
        {
            Name = "RSAT-AD-PowerShell"
            Ensure = "Present"
        }

        Computer DomainJoin
        {
            Name = $env:COMPUTERNAME
            DomainName = $DomainName
            Credential = $AdminCreds
        }

        xCluster CreateCluster
        {
            Name                          = $ClusterName
            StaticIPAddress               = $ClusterIPandSubNetClass
            FirstNode                     = $FirstNode
            DomainAdministratorCredential = $Admincreds
            DependsOn                     = '[Computer]DomainJoin'
        }

        Script  AddProbeToClusterResource
        {
            GetScript  = {return @{ 'Result' = $(Get-ClusterResource "Cluster IP Address" | Get-ClusterParameter -Name ProbePort ).Value} }
                                
            SetScript  = {
                            
                            Get-ClusterResource "Cluster IP Address"| Set-ClusterParameter -Multiple @{"Address"="$using:ClusterStaticIP";"ProbePort"=59999;"SubnetMask"="$using:ClusterIPSubnetMask";"Network"="Cluster Network 1";"EnableDhcp"=0}
                        }
            TestScript = {
                             return($(Get-ClusterResource -name "Cluster IP Address" | Get-ClusterParameter -Name ProbePort ).Value -eq 59999)
                         }

            PsDscRunAsCredential = $AdminCreds

            DependsON = "[xCluster]CreateCluster"
        }

        xClusterQuorum 'SetQuorumToNodeAndCloudMajority'
        {
            IsSingleInstance        = 'Yes'
            Type                    = 'NodeAndCloudMajority'
            Resource                = $CloudWitnessName
            StorageAccountAccessKey = $($CloudWitnessKey.GetNetworkCredential().Password)

            DependsON = '[xCluster]CreateCluster'
        }

        #Script IncreaseClusterTimeouts {
        #    SetScript  = "(Get-Cluster).SameSubnetDelay = 2000; (Get-Cluster).SameSubnetThreshold = 15; (Get-Cluster).CrossSubnetDelay = 3000; (Get-Cluster).CrossSubnetThreshold = 15"
        #    TestScript = "(Get-Cluster).SameSubnetDelay -eq 2000 -and (Get-Cluster).SameSubnetThreshold -eq 15 -and (Get-Cluster).CrossSubnetDelay -eq 3000 -and (Get-Cluster).CrossSubnetThreshold -eq 15"
        #    GetScript  = "@{Ensure = if ((Get-Cluster).SameSubnetDelay -eq 2000 -and (Get-Cluster).SameSubnetThreshold -eq 15 -and (Get-Cluster).CrossSubnetDelay -eq 3000 -and (Get-Cluster).CrossSubnetThreshold -eq 15) {'Present'} else {'Absent'}}"
        #    DependsOn  = '[xClusterQuorum]SetQuorumToNodeAndCloudMajority'
        #}

        PowerPlan HighPerf
        {
          IsSingleInstance = 'Yes'
          Name             = 'High performance'
        }

        TimeZone SetTimeZone
        {
            IsSingleInstance = 'Yes'
            TimeZone         = $TimeZone
        }

        Script CleanSQL
        {
            SetScript  = 'C:\SQLServerFull\Setup.exe /Action=Uninstall /FEATURES=SQL,AS,RS,IS /INSTANCENAME=MSSQLSERVER /Q'
            TestScript = "(test-path -Path `"C:\Program Files\Microsoft SQL Server\$SQLLocation.MSSQLSERVER\MSSQL\DATA\master.mdf`") -eq `$false"
            GetScript  = "@{Ensure = if ((test-path -Path `"C:\Program Files\Microsoft SQL Server\$SQLLocation.MSSQLSERVER\MSSQL\DATA\master.mdf`") -eq `$false) {'Present'} Else {'Absent'}}"
            DependsON = '[Computer]DomainJoin'
        }

        xPendingReboot Reboot1
        {
            Name = 'Reboot1'
            dependson = '[Script]CleanSQL'
        }
        
        Script  SQLClusterConnectivity
        {
            GetScript  = {return @{ 'Result' = $(Invoke-Sqlcmd -query "Select @@servername" -ServerInstance $using:sqlClusterName -ErrorAction SilentlyContinue).Column1 }}
                                
            SetScript  = {
                                $RetryIntervalSec =30
                                $RetryCount =40
                                for ($count = 0; $count -lt $RetryCount; $count++)
                                {
                                    try
                                    {
                                        $test = Invoke-Sqlcmd -query "Select @@servername" -ServerInstance $using:sqlClusterName -ErrorAction SilentlyContinue
                                        if ($null -eq $test -or $null -eq $test.Column1)
                                        {
                                            Write-Verbose -Message "$using:sqlClusterName not found"
                                            break
                                        }

                                        if ($test.Column1 -ne $using:sqlClusterName)
                                        {
                                            Write-Verbose -Message "$using:sqlClusterName Found!"
                                            $clusterFound = $true
                                            break
                                        }
                                    }
                                    catch
                                    {

                                    }
                                      Write-Verbose -Message "$using:sqlClusterName not found rety in $using:RetryIntervalSec"
                                      Start-Sleep -Seconds $using:RetryIntervalSec
                                    
                                }
                                
                                if (-not $clusterFound)
                                {
                                    Write-Verbose -Message "$using:sqlClusterName not found rety in allotted time!"
                                }
                         }
            TestScript = {  try
                            {
                                $test = Invoke-Sqlcmd -query "Select @@servername" -ServerInstance $using:sqlClusterName -ErrorAction SilentlyContinue
                                if ($test)
                                {
                                    if ($test.Column1 -eq $using:sqlClusterName)
                                    {return($true)}
                                    else 
                                    {return($false)}
                                }
                                else {
                                    return($false)
                                }
                            }
                            Catch
                            {
                                Write-Verbose -Message "$using:sqlClusterName unavailable."
                                return($false)
                            }
                         }

            PsDscRunAsCredential = $AdminCreds

            DependsON = '[xPendingReboot]Reboot1'
        }

        SqlSetup 'InstallNamedInstance'
        {
            Action                = 'AddNode' 
            UpdateEnabled         = 'False'
            ForceReboot           = $false
            SourcePath            = $SourcePath

            InstanceName          = $SQLInstanceName
            Features              = $SQLFeatures
            SQLSvcAccount         = $SQLServicecreds
            AgtSvcAccount         = $AgtServicecreds
            FailoverClusterNetworkName = $SQLClusterName

            PsDscRunAsCredential  = $AdminCreds

            DependsOn             = '[xPendingReboot]Reboot1','[Script]SQLClusterConnectivity'
        }

        UserRightsAssignment PerformVolumeMaintenanceTasks
        {
            Policy = "Perform_volume_maintenance_tasks"
            Identity = $SQLServicecreds.UserName

            DependsOn                     = '[Computer]DomainJoin'
        }

        UserRightsAssignment LockPagesInMemory
        {
            Policy = "Lock_pages_in_memory"
            Identity = $SQLServicecreds.UserName

            DependsOn                     = '[Computer]DomainJoin'
        }

        SqlWindowsFirewall Create_FirewallRules
        {
            Ensure           = 'Present'
            Features         = $SQLFeatures
            InstanceName     = $SQLInstanceName
            SourcePath       = 'C:\SQLServerFull'

            DependsOn = '[SqlSetup]InstallNamedInstance'
        }
    }
}


function WaitForSqlSetup
{
    # Wait for SQL Server Setup to finish before proceeding.
    while ($true)
    {
        try
        {
            Get-ScheduledTaskInfo "\ConfigureSqlImageTasks\RunConfigureImage" -ErrorAction Stop
            Start-Sleep -Seconds 5
        }
        catch
        {
            break
        }
    }
}



$ConfigData = @{
    AllNodes = @(
    @{
        NodeName = 'localhost'
        PSDscAllowPlainTextPassword = $true
    }
    )
}

#  $AdminCreds = Get-Credential
# $SQLServicecreds = $AdminCreds
# FCISQLServer -DomainName tamz.local -Admincreds $AdminCreds -SQLServicecreds $SQLServicecreds -imageoffer "SQL2016SP1-WS2016" -TimeZone "Eastern Standard Time" -ClusterName AES3000-c -FirstNode AES3000-1 -SQLStaticIP "10.50.2.56" -ClusterIPSubnetMask "255.255.255.0" -SQLClusterName "SQLTESTCluster" -ClusterStaticIP "10.50.2.55" -SQLFeatures "SQLENGINE" -SQLInstanceName "MSSQLSERVER" -ClusterIPSubnetClass "24" -Verbose -ConfigurationData $ConfigData -OutputPath d:\
# Start-DscConfiguration -wait -Force -Verbose -Path D:\


