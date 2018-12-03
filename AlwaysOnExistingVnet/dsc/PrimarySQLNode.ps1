configuration AlwaysOnSQLServer
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

    Import-DscResource -ModuleName ComputerManagementdsc,sqlserverdsc,xFailOverCluster,xPendingReboot
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
            RebootNodeIfNeeded = $true
            ActionAfterReboot = 'ContinueConfiguration'
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
            StaticIPAddress               = $ClusterStaticIP
            FirstNode                     = $FirstNode
            DomainAdministratorCredential = $Admincreds
            DependsOn                     = '[Computer]DomainJoin'
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

        xPendingReboot Reboot1
        {
            Name = 'Reboot1'
            dependson = '[Computer]DomainJoin','[Script]CleanSQL'
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

            PsDscRunAsCredential  = $AdminCreds

            DependsOn             = '[Script]CleanSQL','[Computer]DomainJoin'
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
        
        SqlAlwaysOnService 'EnableAlwaysOn'
        {
            Ensure               = 'Present'
            ServerName           = 'LOCALHOST'
            InstanceName         = 'MSSQLSERVER'
            RestartTimeout       = 120
            PsDscRunAsCredential = $AdminCreds
            DependsOn = '[SqlSetup]InstallNamedInstance', '[xCluster]CreateCluster'
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
 # AlwaysOnSQLServer -DomainName tamz.local -Admincreds $AdminCreds -ClusterName AES3000-c -ClusterStaticIP "10.50.2.55/24" -Verbose -ConfigurationData $ConfigData -OutputPath d:\
 #Start-DscConfiguration -wait -Force -Verbose -Path D:\
