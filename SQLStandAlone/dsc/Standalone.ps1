
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
        
        [Int]$RetryCount = 20,
        [Int]$RetryIntervalSec = 30


    )

    Import-DscResource -ModuleName xComputerManagement, xActiveDirectory, xPendingReboot, sqlserverdsc
    $SQLVersion = $imageoffer.Substring(5,2)
    $SQLLocation = "MSSQL$(switch ($SQLVersion){17 {14} 16 {13}})"
    $masterdbpath = "C:\Program Files\Microsoft SQL Server\$SQLLocation.MSSQLSERVER\MSSQL\DATA\master.mdf"

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
            SetScript  = 'C:\SQLServerFull\Setup.exe /Action=Uninstall /FEATURES=SQL,AS,RS,IS /INSTANCENAME=MSSQLSERVER /Q'
            TestScript = "(test-path -Path $masterdbpath) -eq:0"
            GetScript  = "@{Ensure = if ((test-path -Path $masterdbpath) -eq:0) {'Present'} Else {'Absent'}}"
        }

        Script AddDataDisks {
            SetScript  = 
@"                      
                        New-StoragePool -FriendlyName 'SQLPool' -StorageSubSystemFriendlyName "Windows Storage*" -PhysicalDisks (Get-PhysicalDisk -canpool:1) 
                        New-Volume -StoragePoolFriendlyName SQLPool* -FriendlyName $datadrivelabel -FileSystem NTFS -AllocationUnitSize 65536 -DriveLetter $datadriveletter -size $datadriveSize;
                        New-Volume -StoragePoolFriendlyName SQLPool* -FriendlyName $logdrivelabel -FileSystem NTFS -AllocationUnitSize 65536 -DriveLetter $logdriveletter -size $logdrivesize;
                        New-Volume -StoragePoolFriendlyName SQLPool* -FriendlyName $tempdbdrivelabel -FileSystem NTFS -AllocationUnitSize 65536 -DriveLetter $tempdbdriveletter -size $tempdbdriveSize;
"@
            TestScript = "(Get-StoragePool -FriendlyName SQLPool*).OperationalStatus -eq 'OK'"
            GetScript  = "@{Ensure = if ((Get-StoragePool -FriendlyName SQLPool*).OperationalStatus -eq 'OK') {'Present'} Else {'Absent'}}"
        }
 
        SqlSetup 'InstallNamedInstance'
        {
            InstanceName          = $SQLInstanceName
            Features              = $SQLFeatures
            SQLCollation          = 'SQL_Latin1_General_CP1_CI_AS'
            SQLSysAdminAccounts   = 'TAMZ\DBA'
            InstallSharedDir      = 'C:\Program Files\Microsoft SQL Server'
            InstallSharedWOWDir   = 'C:\Program Files (x86)\Microsoft SQL Server'
            InstanceDir           = "$datadriveletter:\Program Files\Microsoft SQL Server"
            InstallSQLDataDir     = "$datadriveletter:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\"
            SQLUserDBDir          = "$datadriveletter:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\Data"
            SQLUserDBLogDir       = "$logdriveletter:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\Log"
            SQLTempDBDir          = "$tempdbdriveletter:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\TempDb"
            SQLTempDBLogDir       = "$tempdbdriveletter:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\TempDb"
            SQLBackupDir          = "$datadriveletter:\Program Files\Microsoft SQL Server\$SQLLocation.$SQLInstanceName\MSSQL\Backup"
            SourcePath            = 'C:\SQLServerFull'
            UpdateEnabled         = 'False'
            ForceReboot           = $false
            BrowserSvcStartupType = 'Automatic'

            PsDscRunAsCredential  = $localAdminCreds

            DependsOn             = '[Script]CleanSQL','[Script]AddDataDisks'
        }
    }
}
 


