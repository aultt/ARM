
configuration StandAlone
{
    param
    (
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$domainuserCreds,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$localAdminCreds,
        [string]$SQLFeatures,
        [string]$InstanceName,
        [string]$datadriveLetter,
        [string]$datadrivelabel,
        [string]$datadriveSize,
        [string]$logdriveLetter,
        [string]$logdrivelabel,
        [string]$logdriveSize,
        [string]$tempdbdriveLetter,
        [string]$tempdbdrivelabel,
        [string]$tempdbdriveSize,
        
        [Int]$RetryCount = 20,
        [Int]$RetryIntervalSec = 30


    )

    Import-DscResource -ModuleName xComputerManagement, xActiveDirectory, xPendingReboot, sqlserverdsc

    Node localhost
    {
        # Set LCM to reboot if needed
        LocalConfigurationManager {
            DebugMode          = "ForceModuleImport"
            RebootNodeIfNeeded = $true
            ActionafterReboot = 'ContinueConfiguration'
        }
        
        xComputer DomainJoin
        {
            Name       = $env:COMPUTERNAME
            DomainName = $DomainName
            Credential = $domainuserCreds
        }
        xPendingReboot Reboot1
        {
            Name = 'Reboot1'
            dependson = '[xComputer]DomainJoin'
        }

        Script CleanSQL
        {
            SetScript = 'C:\SQLServerFull\Setup.exe /Action=Uninstall /FEATURES=SQL,AS,IS,RS /INSTANCENAME=MSSQLSERVER /Q'
            TestScript = '(test-path -Path "C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\DATA\master.mdf") -eq $false'
            GetScript = '@{Ensure = if ((test-path -Path "C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\DATA\master.mdf") -eq $false) {"Present"} Else {"Absent"}}'
            DependsOn = "[xComputer]DomainJoin"
        }

        Script AddDataDisks {
            SetScript  = 
@"                      
                        $physicalDisks = (Get-PhysicalDisk -canpool $true)
                        New-StoragePool -FriendlyName 'SQLPool' -StorageSubSystemFriendlyName "Windows Storage*" -PhysicalDisks $physicalDisks 
                        New-Volume -StoragePoolFriendlyName SQLPool* -FriendlyName ${datadrivelabel} -FileSystem NTFS -AllocationUnitSize 65536 -DriveLetter ${datadriveLetter} -size ${datadriveSize};
                        New-Volume -StoragePoolFriendlyName SQLPool* -FriendlyName ${logdrivelabel} -FileSystem NTFS -AllocationUnitSize 65536 -DriveLetter ${logdriveLetter} -size ${logdriveSize};
                        New-Volume -StoragePoolFriendlyName SQLPool* -FriendlyName ${tempdbdrivelabel} -FileSystem NTFS -AllocationUnitSize 65536 -DriveLetter ${tempdbdriveLetter} -size ${tempdbdriveSize};
"@
            TestScript = "(Get-StoragePool -FriendlyName SQLPool*).OperationalStatus -eq 'OK'"
            GetScript  = "@{Ensure = if ((Get-StoragePool -FriendlyName SQLPool*).OperationalStatus -eq 'OK') {'Present'} Else {'Absent'}}"
        }

        SqlSetup 'InstallNamedInstance'
        {
            InstanceName          = $InstanceName
            Features              = $SQLFeatures
            SQLCollation          = 'SQL_Latin1_General_CP1_CI_AS'
            SQLSysAdminAccounts   = 'TAMZ\DBA'
            InstallSharedDir      = 'C:\Program Files\Microsoft SQL Server'
            InstallSharedWOWDir   = 'C:\Program Files (x86)\Microsoft SQL Server'
            InstanceDir           = 'G:\Program Files\Microsoft SQL Server'
            InstallSQLDataDir     = "G:\Program Files\Microsoft SQL Server\MSSQL13.$InstanceName\MSSQL\Data"
            SQLUserDBDir          = "G:\Program Files\Microsoft SQL Server\MSSQL13.$InstanceName\MSSQL\Data"
            SQLUserDBLogDir       = "F:\Program Files\Microsoft SQL Server\MSSQL13.$InstanceName\MSSQL\Data"
            SQLTempDBDir          = "T:\Program Files\Microsoft SQL Server\MSSQL13.$InstanceName\MSSQL\Data"
            SQLTempDBLogDir       = "T:\Program Files\Microsoft SQL Server\MSSQL13.$InstanceName\MSSQL\Data"
            SQLBackupDir          = "G:\Program Files\Microsoft SQL Server\MSSQL13.$InstanceName\MSSQL\Backup"
            SourcePath            = 'C:\SQLServerFull'
            UpdateEnabled         = 'False'
            ForceReboot           = $false
            BrowserSvcStartupType = 'Automatic'

            PsDscRunAsCredential  = $localAdminCreds

            DependsOn             = '[Script]CleanSQL','[Script]AddDataDisks'
        }

        #SqlServerLogin Add_DBAGroup
        #{
        #    Ensure               = 'Present'
        #    Name                 = 'TAMZ\DBA'
        #    LoginType            = 'WindowsGroup'
        #    ServerName           = $env:COMPUTERNAME
        #    InstanceName         = 'MSSQLSERVER'
        #    PsDscRunAsCredential = $localAdminCreds
#
        #    dependson = "[sqlSetup]InstallNamedInstance"
        #}
        #SqlServerRole AddDBAToSysAdmin
        #{
        #    Ensure               = 'Present'
        #    ServerRoleName       = 'sysadmin'
        #    MembersToInclude     = 'TAMZ\DBA'
        #    ServerName           = $env:COMPUTERNAME
        #    InstanceName         = 'MSSQLSERVER'
        #    PsDscRunAsCredential = $localAdminCreds
#
        #    dependson = '[SqlServerLogin]Add_DBAGroup'
        #}
    }
}



