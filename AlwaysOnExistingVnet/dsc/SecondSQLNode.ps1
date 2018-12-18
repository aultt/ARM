
configuration AlwaysOnSqlServer
{
    param
    (
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$SQLServicecreds,
        [string]$imageoffer = "SQL2016-WS2016",
        [string]$SQLFeatures = "SQLENGINE",
        [string]$SQLInstanceName = "MSSQLSERVER",
        [string]$datadriveLetter = 'C',
        [string]$logdriveLetter = 'C',
        [string]$tempdbdriveLetter = 'C',
        [string]$SQLSysAdmins = 'TAMZ\DBA',
        [string]$SourcePath = 'C:\SQLServerFull',
        [Parameter(Mandatory)]
        [string]$ClusterName,
        [Parameter(Mandatory)]
        [string]$ClusterStaticIP,
        [Parameter(Mandatory)]
        [string]$ClusterIPSubnetClass,
        [Parameter(Mandatory)]
        [string]$FirstNode,
        [Parameter(Mandatory)]
        [string]$AvailabilityGroupName,
        [Parameter(Mandatory)]
        [string]$ListenerStaticIP,
        [Parameter(Mandatory)]
        [string]$ListenerSubnetMask,
        [string]$SQLPort=1433,
        [Parameter(Mandatory)]
        [string]$CloudWitnessName,
        [string]$TimeZone ="Eastern Standard Time",
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$CloudWitnessKey, 

        [Int]$RetryCount = 20,
        [Int]$RetryIntervalSec = 30
    )

    
    Import-DscResource -ModuleName ComputerManagementdsc, sqlserverdsc, xFailOverCluster, xPendingReboot
    
    $ClusterIPandSubNetClass = $ClusterStaticIP + '/' +$ClusterIPSubnetClass
    $ListenerIPandMask = $ListenerStaticIP + '/'+$ListenerSubnetMask
    $SQLVersion = $imageoffer.Substring(5,2)
    $SQLLocation = "MSSQL$(switch ($SQLVersion){17 {14} 16 {13}})"
    $IPResourceName = $AvailabilityGroupName +'_'+ $ListenerStaticIP

    WaitForSqlSetup

    Node localhost
    {
        LocalConfigurationManager 
        {
            RebootNodeIfNeeded = $True
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

        Computer DomainJoin
        {
            Name = $env:COMPUTERNAME
            DomainName = $DomainName
            Credential = $Admincreds
        }

        xWaitForCluster WaitForCluster
        {
            Name             = $ClusterName
            RetryIntervalSec = 10
            RetryCount       = 60
            DependsOn        = '[WindowsFeature]AddRemoteServerAdministrationToolsClusteringCmdInterfaceFeature','[xPendingReboot]Reboot1'
        }

        xCluster JoinSecondNodeToCluster
        {
            Name                          = $ClusterName
            FirstNode                     = $FirstNode
            StaticIPAddress               = $ClusterIPandSubNetClass
            DomainAdministratorCredential = $Admincreds
            DependsOn                     = '[xWaitForCluster]WaitForCluster','[Computer]DomainJoin'
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

        SqlSetup 'InstallNamedInstance'
        {
            InstanceName          = $SQLInstanceName
            Features              = $SQLFeatures
            SQLCollation          = 'SQL_Latin1_General_CP1_CI_AS'
            SQLSvcAccount         = $SQLServicecreds
            SQLSysAdminAccounts   = $SQLSysAdmins
            InstallSharedDir      = 'C:\Program Files\Microsoft SQL Server'
            InstallSharedWOWDir   = 'C:\Program Files (x86)\Microsoft SQL Server'
            InstanceDir           = "${datadriveletter}:\Program Files\Microsoft SQL Server"
            InstallSQLDataDir     = "${datadriveletter}:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\"
            SQLUserDBDir          = "${datadriveletter}:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\Data"
            SQLUserDBLogDir       = "${logdriveletter}:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\Log"
            SQLTempDBDir          = "${tempdbdriveLetter}:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\Data"
            SQLTempDBLogDir       = "${logdriveletter}:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\Data"
            SQLBackupDir          = "${datadriveletter}:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\Backup"
            SourcePath            = $SourcePath 
            UpdateEnabled         = 'False'
            ForceReboot           = $false
            BrowserSvcStartupType = 'Automatic'

            PsDscRunAsCredential  = $Admincreds

            DependsOn             = '[xPendingReboot]Reboot1'
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
            PsDscRunAsCredential    = $Admincreds

            DependsOn = '[SqlSetup]InstallNamedInstance'
        }

        SqlServerMemory Set_SQLServerMaxMemory_ToAuto
        {
            Ensure                  = 'Present'
            DynamicAlloc            = $true
            InstanceName            = $SQLInstanceName
            PsDscRunAsCredential    = $Admincreds

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
        
        SqlServerLogin AddNTServiceClusSvc
        {
            Ensure               = 'Present'
            Name                 = 'NT SERVICE\ClusSvc'
            LoginType            = 'WindowsUser'
            ServerName           = $env:COMPUTERNAME
            InstanceName         = $SQLInstanceName
            PsDscRunAsCredential = $AdminCreds
            
            DependsOn = '[SqlSetup]InstallNamedInstance', '[xCluster]JoinSecondNodeToCluster'
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

        # Create a DatabaseMirroring endpoint
        SqlServerEndpoint HADREndpoint
        {
            EndPointName         = 'HADR'
            Ensure               = 'Present'
            Port                 = 5022
            ServerName           = $env:COMPUTERNAME
            InstanceName         = $SQLInstanceName
            PsDscRunAsCredential = $AdminCreds

            DependsOn = '[SqlSetup]InstallNamedInstance', '[xCluster]JoinSecondNodeToCluster'
        }

        SqlAlwaysOnService 'EnableAlwaysOn'
        {
            Ensure               = 'Present'
            ServerName           = $env:COMPUTERNAME
            InstanceName         = $SQLInstanceName
            RestartTimeout       = 120
            PsDscRunAsCredential = $Admincreds

            DependsOn = '[SqlSetup]InstallNamedInstance','[xCluster]JoinSecondNodeToCluster'
        }

        xPendingReboot Reboot2
        {
            Name = 'Reboot2'
            dependson = '[SqlAlwaysOnService]EnableAlwaysOn'
        }

        SqlWaitForAG 'SQLConfigureAG-WaitAG'
        {
            Name                 = $AvailabilityGroupName
            RetryIntervalSec     = 30
            RetryCount           = 40
            PsDscRunAsCredential = $SqlAdministratorCredential

            DependsOn = '[xPendingReboot]Reboot2'
        }

        SqlAGReplica AddReplica
        {
            Ensure                     = 'Present'
            Name                       = $env:COMPUTERNAME
            AvailabilityGroupName      = $AvailabilityGroupName
            ServerName                 = $env:COMPUTERNAME
            InstanceName               = $SQLInstanceName
            PrimaryReplicaServerName   = $FirstNode
            PrimaryReplicaInstanceName = $SQLInstanceName
            ProcessOnlyOnActiveNode    = 1
            PsDscRunAsCredential = $AdminCreds
        
            DependsOn                  = '[SqlWaitForAG]SQLConfigureAG-WaitAG'
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
# AlwaysOnSQLServer -DomainName tamz.local -Admincreds $AdminCreds -SQLServicecreds $SQLServicecreds -ClusterName AES3000-c -FirstNode AES3000-1 -ListenerStaticIP "10.50.2.56" -ListenerSubnetMask "255.255.255.0" -availabilityGroupName "TestAG" -ClusterStaticIP "10.50.2.55" -ClusterIPSubnetClass "24" -Verbose -ConfigurationData $ConfigData -OutputPath d:\
# Start-DscConfiguration -wait -Force -Verbose -Path D:\


