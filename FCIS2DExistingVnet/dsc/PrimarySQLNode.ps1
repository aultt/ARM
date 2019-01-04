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
    #$ListenerIPandMask = $ListenerStaticIP + '/'+$ClusterIPSubnetMask
    #$IPResourceName = $AvailabilityGroupName +'_'+ $ListenerStaticIP

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
        #
        #WaitForDisk DataVolume{
        #    DiskId = 2
        #    RetryIntervalSec = 60
        #    RetryCount =60
        #}

        #Disk DataVolume{
        #    DiskId =  2
        #    DriveLetter = $datadriveLetter
        #    FSFormat = 'NTFS'
        #    AllocationUnitSize = 64kb
        #    DependsOn = '[WaitForDisk]DataVolume'
        #}
#
        #WaitForDisk LogVolume{
        #    DiskId = 3
        #    RetryIntervalSec = 60
        #    RetryCount =60
        #}
#
        #Disk LogVolume{
        #    DiskId =  3
        #    DriveLetter = $logdriveLetter
        #    FSFormat = 'NTFS'
        #    AllocationUnitSize = 64kb
        #    DependsOn = '[WaitForDisk]LogVolume'
        #}
#
        WindowsFeature FC
        {
            Name = "Failover-Clustering"
            Ensure = "Present"
        }

		WindowsFeature FailoverClusterTools 
        { 
            Ensure = "Present" 
            Name = "RSAT-Clustering-Mgmt"
			DependsOn = "[WindowsFeature]FC"
        } 

        WindowsFeature FCPS
        {
            Name = "RSAT-Clustering-PowerShell"
            Ensure = "Present"
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

        #SqlSetup 'InstallNamedInstance'
        #{
        #    InstanceName          = $SQLInstanceName
        #    Features              = $SQLFeatures
        #    SQLCollation          = 'SQL_Latin1_General_CP1_CI_AS'
        #    SQLSvcAccount         = $SQLServicecreds
        #    SQLSysAdminAccounts   = $SQLSysAdmins
        #    InstallSharedDir      = 'C:\Program Files\Microsoft SQL Server'
        #    InstallSharedWOWDir   = 'C:\Program Files (x86)\Microsoft SQL Server'
        #    InstanceDir           = "${datadriveletter}:\Program Files\Microsoft SQL Server"
        #    InstallSQLDataDir     = "${datadriveletter}:\Program Files\Microsoft SQL Server\"
        #    SQLUserDBDir          = "${datadriveletter}:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\Data"
        #    SQLUserDBLogDir       = "${logdriveletter}:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\Log"
        #    SQLTempDBDir          = "${tempdbdriveLetter}:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\Data"
        #    SQLTempDBLogDir       = "${logdriveletter}:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\Log"
        #    SQLBackupDir          = "${datadriveletter}:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\Backup"
        #    SourcePath            = $SourcePath
        #    UpdateEnabled         = 'False'
        #    ForceReboot           = $false
        #    BrowserSvcStartupType = 'Automatic'
#
        #    PsDscRunAsCredential  = $AdminCreds
#
        #    DependsOn             = '[xPendingReboot]Reboot1','[Disk]LogVolume','[Disk]DataVolume'
        #}
#
        #UserRightsAssignment PerformVolumeMaintenanceTasks
        #{
        #    Policy = "Perform_volume_maintenance_tasks"
        #    Identity = $SQLServicecreds.UserName
#
        #    DependsOn                     = '[Computer]DomainJoin'
        #}
#
        #UserRightsAssignment LockPagesInMemory
        #{
        #    Policy = "Lock_pages_in_memory"
        #    Identity = $SQLServicecreds.UserName
#
        #    DependsOn                     = '[Computer]DomainJoin'
        #}
#
        #SqlServerNetwork 'ChangeTcpIpOnDefaultInstance'
        #{
        #    InstanceName         = $SQLInstanceName
        #    ProtocolName         = 'Tcp'
        #    IsEnabled            = $true
        #    TCPDynamicPort       = $false
        #    TCPPort              = $SQLPort
        #    RestartService       = $true
        #    DependsOn = '[SqlSetup]InstallNamedInstance'
        #    
        #    PsDscRunAsCredential = $AdminCreds
        #}
#
        #SqlServerMaxDop Set_SQLServerMaxDop_ToAuto
        #{
        #    Ensure                  = 'Present'
        #    DynamicAlloc            = $true
        #    InstanceName            = $SQLInstanceName
        #    PsDscRunAsCredential    = $AdminCreds
#
        #    DependsOn = '[SqlSetup]InstallNamedInstance'
        #}
#
        #SqlServerMemory Set_SQLServerMaxMemory_ToAuto
        #{
        #    Ensure                  = 'Present'
        #    DynamicAlloc            = $true
        #    InstanceName            = $SQLInstanceName
        #    PsDscRunAsCredential    = $AdminCreds
#
        #    DependsOn = '[SqlSetup]InstallNamedInstance'
        #}
#
        #SqlWindowsFirewall Create_FirewallRules
        #{
        #    Ensure           = 'Present'
        #    Features         = $SQLFeatures
        #    InstanceName     = $SQLInstanceName
        #    SourcePath       = 'C:\SQLServerFull'
#
        #    DependsOn = '[SqlSetup]InstallNamedInstance'
        #}
        # Adding the required service account to allow the cluster to log into SQL
        #SqlServerLogin AddNTServiceClusSvc
        #{
        #    Ensure               = 'Present'
        #    Name                 = 'NT SERVICE\ClusSvc'
        #    LoginType            = 'WindowsUser'
        #    ServerName           = $env:COMPUTERNAME
        #    InstanceName         = $SQLInstanceName
        #    PsDscRunAsCredential = $AdminCreds
        #    
        #    DependsOn = '[SqlSetup]InstallNamedInstance', '[xCluster]CreateCluster'
        #}
#
        ## Add the required permissions to the cluster service login
        #SqlServerPermission AddNTServiceClusSvcPermissions
        #{
        #    
        #    Ensure               = 'Present'
        #    ServerName           = $env:COMPUTERNAME
        #    InstanceName         = $SQLInstanceName
        #    Principal            = 'NT SERVICE\ClusSvc'
        #    Permission           = 'AlterAnyAvailabilityGroup', 'ViewServerState'
        #    PsDscRunAsCredential = $AdminCreds
#
        #    DependsOn            = '[SqlServerLogin]AddNTServiceClusSvc'
        #}
#
        ## Create a DatabaseMirroring endpoint
        #SqlServerEndpoint HADREndpoint
        #{
        #    EndPointName         = 'HADR'
        #    Ensure               = 'Present'
        #    Port                 = 5022
        #    ServerName           = $env:COMPUTERNAME
        #    InstanceName         = $SQLInstanceName
        #    PsDscRunAsCredential = $AdminCreds
#
        #    DependsOn = '[SqlSetup]InstallNamedInstance', '[xCluster]CreateCluster'
        #}
#
        #SqlAlwaysOnService 'EnableAlwaysOn'
        #{
        #    Ensure               = 'Present'
        #    ServerName           = $env:COMPUTERNAME
        #    InstanceName         = $SQLInstanceName
        #    RestartTimeout       = 120
        #    PsDscRunAsCredential = $AdminCreds
        #    DependsOn = '[SqlSetup]InstallNamedInstance', '[xCluster]CreateCluster'
        #}
#
        #SqlAG AddAG
        #{
        #    Ensure               = 'Present'
        #    Name                 = $AvailabilityGroupName
        #    InstanceName         = $SQLInstanceName
        #    ServerName           = $env:COMPUTERNAME
        #
        #    PsDscRunAsCredential = $AdminCreds
        #
        #    DependsOn            = '[SqlAlwaysOnService]EnableAlwaysOn', '[SqlServerEndpoint]HADREndpoint', '[SqlServerPermission]AddNTServiceClusSvcPermissions'
        #}

        #SqlAGListener AvailabilityGroupListenerWithSameNameAsVCO
        #{
        #    Ensure               = 'Present'
        #    ServerName           = $env:COMPUTERNAME
        #    InstanceName         = $SQLInstanceName
        #    AvailabilityGroup    = $AvailabilityGroupName
        #    Name                 = $AvailabilityGroupName
        #    IpAddress            = $ListenerIPandMask
        #    Port                 = $SQLPort
#
        #    PsDscRunAsCredential = $AdminCreds
#
        #    DependsON = '[SqlAG]AddAG'
        #}
        #
        #Script  AddProbeToSQLClusterResource
        #{
        #    GetScript  = {return @{ 'Result' = $(Get-ClusterResource $using:IPResourceName | Get-ClusterParameter -Name ProbePort ).Value} }
        #                        
        #    SetScript  = {
        #                    
        #                    Get-ClusterResource $using:IPResourceName| Set-ClusterParameter -Multiple @{"Address"="$using:ListenerStaticIP";"ProbePort"=59999;"SubnetMask"="$using:ClusterIPSubnetMask";"Network"="Cluster Network 1";"EnableDhcp"=0}
        #                }
        #    TestScript = {
        #                     return($(Get-ClusterResource -name $using:IPResourceName | Get-ClusterParameter -Name ProbePort ).Value -eq 59999)
        #                 }
#
        #    PsDscRunAsCredential = $AdminCreds
#
        #    DependsON = "[SqlAGListener]AvailabilityGroupListenerWithSameNameAsVCO"
        #}
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
# AlwaysOnSQLServer -DomainName tamz.local -Admincreds $AdminCreds -SQLServicecreds $SQLServicecreds -ClusterName AES3000-c -FirstNode AES3000-1 -ListenerStaticIP "10.50.2.56" -ClusterIPSubnetMask "255.255.255.0" -availabilityGroupName "TestAG" -ClusterStaticIP "10.50.2.55" -ClusterIPSubnetClass "24" -Verbose -ConfigurationData $ConfigData -OutputPath d:\
# Start-DscConfiguration -wait -Force -Verbose -Path D:\


