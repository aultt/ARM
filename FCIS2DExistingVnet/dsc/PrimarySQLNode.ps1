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
        
        xWaitForCluster WaitForSQLCluster
        {
            Name             = $SQLClusterName
            RetryIntervalSec = 10
            RetryCount       = 60
            DependsOn        = '[xClusterQuorum]SetQuorumToNodeAndCloudMajority'
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
            FailoverClusterNetworkName = $SQLClusterName

            PsDscRunAsCredential  = $AdminCreds

            DependsOn             = '[xPendingReboot]Reboot1','[xWaitForCluster]WaitForSQLCluster'
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

        SqlServerNetwork 'ChangeTcpIpOnDefaultInstance'
        {
            InstanceName         = $SQLInstanceName
            ProtocolName         = 'Tcp'
            IsEnabled            = $true
            TCPDynamicPort       = $false
            TCPPort              = $SQLPort
            RestartService       = $true
            DependsOn = '[SqlSetup]InstallNamedInstance'
            
            PsDscRunAsCredential = $AdminCreds
        }

        SqlServerMaxDop Set_SQLServerMaxDop_ToAuto
        {
            Ensure                  = 'Present'
            DynamicAlloc            = $true
            InstanceName            = $SQLInstanceName
            PsDscRunAsCredential    = $AdminCreds

            DependsOn = '[SqlSetup]InstallNamedInstance'
        }

        SqlServerMemory Set_SQLServerMaxMemory_ToAuto
        {
            Ensure                  = 'Present'
            DynamicAlloc            = $true
            InstanceName            = $SQLInstanceName
            PsDscRunAsCredential    = $AdminCreds

            DependsOn = '[SqlSetup]InstallNamedInstance'
        }

        SqlWindowsFirewall Create_FirewallRules
        {
            Ensure           = 'Present'
            Features         = $SQLFeatures
            InstanceName     = $SQLInstanceName
            SourcePath       = 'C:\SQLServerFull'

            DependsOn = '[SqlSetup]InstallNamedInstance'
        }
        #Adding the required service account to allow the cluster to log into SQL
        SqlServerLogin AddNTServiceClusSvc
        {
            Ensure               = 'Present'
            Name                 = 'NT SERVICE\ClusSvc'
            LoginType            = 'WindowsUser'
            ServerName           = $env:COMPUTERNAME
            InstanceName         = $SQLInstanceName
            PsDscRunAsCredential = $AdminCreds
            
            DependsOn = '[SqlSetup]InstallNamedInstance', '[xCluster]CreateCluster'
        }

        # Add the required permissions to the cluster service login
        SqlServerPermission AddNTServiceClusSvcPermissions
        {
            
            Ensure               = 'Present'
            ServerName           = $env:COMPUTERNAME
            InstanceName         = $SQLInstanceName
            Principal            = 'NT SERVICE\ClusSvc'
            Permission           = 'AlterAnyAvailabilityGroup', 'ViewServerState'
            PsDscRunAsCredential = $AdminCreds

            DependsOn            = '[SqlServerLogin]AddNTServiceClusSvc'
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
# AlwaysOnSQLServer -DomainName tamz.local -Admincreds $AdminCreds -SQLServicecreds $SQLServicecreds -ClusterName AES3000-c -FirstNode AES3000-1 -ListenerStaticIP "10.50.2.56" -ClusterIPSubnetMask "255.255.255.0" -availabilityGroupName "TestAG" -ClusterStaticIP "10.50.2.55" -ClusterIPSubnetClass "24" -Verbose -ConfigurationData $ConfigData -OutputPath d:\
# Start-DscConfiguration -wait -Force -Verbose -Path D:\


