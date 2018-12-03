
configuration AlwaysOnSqlServer
{
    param
    (
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        #[Parameter(Mandatory)]
        #[System.Management.Automation.PSCredential]$SQLServicecreds,
        [string]$imageoffer = "SQL2016-WS2016",
        [string]$SQLFeatures = "SQLENGINE",
        [string]$SQLInstanceName = "MSSQLSERVER",
        [string]$datadriveLetter = 'C',
        #[string]$datadrivelabel,
        #[string]$datadriveSize,
        [string]$logdriveLetter = 'C',
        #[string]$logdrivelabel,
        #[string]$logdriveSize,
        [string]$tempdbdriveLetter = 'D',
        #[string]$tempdbdrivelabel,
        #[string]$tempdbdriveSize,
        [string]$ClusterName,
        [string]$ClusterStaticIP,
        [string]$FirstNode,

        [Int]$RetryCount = 20,
        [Int]$RetryIntervalSec = 30
    )

    
    Import-DscResource -ModuleName ComputerManagementdsc, sqlserverdsc, xFailOverCluster, xPendingReboot
    #[System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ($Admincreds.UserName, $Admincreds.Password)
    #[System.Management.Automation.PSCredential]$DomainFQDNCreds = New-Object System.Management.Automation.PSCredential ($Admincreds.UserName, $Admincreds.Password)
    #[System.Management.Automation.PSCredential]$SQLCreds = New-Object System.Management.Automation.PSCredential ($Admincreds.UserName, $Admincreds.Password)

    $SQLVersion = $imageoffer.Substring(5,2)
    $SQLLocation = "MSSQL$(switch ($SQLVersion){17 {14} 16 {13}})"
    
    WaitForSqlSetup

    Node localhost
    {
        LocalConfigurationManager 
        {
            RebootNodeIfNeeded = $True
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
            DependsOn        = '[WindowsFeature]AddRemoteServerAdministrationToolsClusteringCmdInterfaceFeature'
        }

        xCluster JoinSecondNodeToCluster
        {
            Name                          = $ClusterName
            FirstNode                     = $FirstNode
            StaticIPAddress               = $ClusterStaticIP
            DomainAdministratorCredential = $Admincreds
            DependsOn                     = '[xWaitForCluster]WaitForCluster','[Computer]DomainJoin'
        }
        
        PowerPlan HighPerf
        {
          IsSingleInstance = 'Yes'
          Name             = 'High performance'
        }

        TimeZone TimeZoneExample
        {
            IsSingleInstance = 'Yes'
            TimeZone         = 'Eastern Standard Time'
        }
        
        Script CleanSQL
        {
            SetScript  = 'C:\SQLServerFull\Setup.exe /Action=Uninstall /FEATURES=SQL,AS,RS,IS /INSTANCENAME=MSSQLSERVER /Q'
            TestScript = "(test-path -Path `"C:\Program Files\Microsoft SQL Server\$SQLLocation.MSSQLSERVER\MSSQL\DATA\master.mdf`") -eq `$false"
            GetScript  = "@{Ensure = if ((test-path -Path `"C:\Program Files\Microsoft SQL Server\$SQLLocation.MSSQLSERVER\MSSQL\DATA\master.mdf`") -eq `$false) {'Present'} Else {'Absent'}}"
        }     

        SqlSetup 'InstallNamedInstance'
        {
            InstanceName          = $SQLInstanceName
            Features              = $SQLFeatures
            SQLCollation          = 'SQL_Latin1_General_CP1_CI_AS'
            SQLSysAdminAccounts   = 'TAMZ\DBA'
            InstallSharedDir      = 'C:\Program Files\Microsoft SQL Server'
            InstallSharedWOWDir   = 'C:\Program Files (x86)\Microsoft SQL Server'
            InstanceDir           = "${datadriveletter}:\Program Files\Microsoft SQL Server"
            InstallSQLDataDir     = "${datadriveletter}:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\"
            SQLUserDBDir          = "${datadriveletter}:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\Data"
            SQLUserDBLogDir       = "${logdriveletter}:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\Log"
            SQLTempDBDir          = "${tempdbdriveletter}:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\TempDb"
            SQLTempDBLogDir       = "${tempdbdriveletter}:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\TempDb"
            SQLBackupDir          = "${datadriveletter}:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\Backup"
            SourcePath            = 'C:\SQLServerFull'
            UpdateEnabled         = 'False'
            ForceReboot           = $false
            BrowserSvcStartupType = 'Automatic'

            PsDscRunAsCredential  = $Admincreds

            DependsOn             = '[Script]CleanSQL'
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
        
        SqlAlwaysOnService 'EnableAlwaysOn'
        {
            Ensure               = 'Present'
            ServerName           = 'LOCALHOST'
            InstanceName         = 'MSSQLSERVER'
            RestartTimeout       = 120
            PsDscRunAsCredential = $Admincreds

            DependsOn = '[SqlSetup]InstallNamedInstance','[xCluster]JoinSecondNodeToCluster'
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

#$AdminCreds = Get-Credential
#$SvcCreds = $AdminCreds
 #SecondaryAlwaysOnSqlServer -DomainName tamz.local -Admincreds $AdminCreds -SQLServicecreds $SvcCreds -Verbose -ConfigurationData $ConfigData -OutputPath d:\
 #Start-DscConfiguration -wait -Force -Verbose -Path D:\
