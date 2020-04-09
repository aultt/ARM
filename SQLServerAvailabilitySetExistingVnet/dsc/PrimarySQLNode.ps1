configuration AlwaysOnSQLServer
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
        [string]$logdriveLetter,
        [string]$tempdbdriveLetter,
        [string]$SQLSysAdmins,
        [string]$SourcePath,
        [Parameter(Mandatory)]
        [string]$FirstNode,
        [string]$SQLPort=1433,
        [Parameter(Mandatory)]
        [string]$TimeZone,
        [Int]$RetryCount = 20,
        [Int]$RetryIntervalSec = 30

    )

    Import-DscResource -ModuleName ComputerManagementdsc,sqlserverdsc,xFailOverCluster,xPendingReboot,Storagedsc,SecurityPolicydsc

    $SQLVersion = $imageoffer.Substring(5,2)
    $SQLLocation = "MSSQL$(switch ($SQLVersion){19 {15} 17 {14} 16 {13}})"

    WaitForSqlSetup

    Node localhost
    {
        LocalConfigurationManager 
        {
            RebootNodeIfNeeded = $true
            ActionAfterReboot = 'ContinueConfiguration'
        }
        
        WaitForDisk DataVolume{
            DiskId = 2
            RetryIntervalSec = 60
            RetryCount =60
        }

        Disk DataVolume{
            DiskId =  2
            DriveLetter = $datadriveLetter
            FSFormat = 'NTFS'
            AllocationUnitSize = 64kb
            DependsOn = '[WaitForDisk]DataVolume'
        }

        WaitForDisk LogVolume{
            DiskId = 3
            RetryIntervalSec = 60
            RetryCount =60
        }

        Disk LogVolume{
            DiskId =  3
            DriveLetter = $logdriveLetter
            FSFormat = 'NTFS'
            AllocationUnitSize = 64kb
            DependsOn = '[WaitForDisk]LogVolume'
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
            InstallSQLDataDir     = "${datadriveletter}:\Program Files\Microsoft SQL Server\"
            SQLUserDBDir          = "${datadriveletter}:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\Data"
            SQLUserDBLogDir       = "${logdriveletter}:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\Log"
            SQLTempDBDir          = "${tempdbdriveLetter}:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\Data"
            SQLTempDBLogDir       = "${logdriveletter}:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\Log"
            SQLBackupDir          = "${datadriveletter}:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\Backup"
            SourcePath            = $SourcePath
            UpdateEnabled         = 'False'
            ForceReboot           = $false
            BrowserSvcStartupType = 'Automatic'

            PsDscRunAsCredential  = $AdminCreds

            DependsOn             = '[xPendingReboot]Reboot1','[Disk]LogVolume','[Disk]DataVolume'
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


