
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
        service sqlserver
        {
            Name = "MSSQLSERVER"
            State = "Running"
        }

        SqlServerLogin Add_DBAGroup
        {
            Ensure               = 'Present'
            Name                 = 'TAMZ\DBA'
            LoginType            = 'WindowsGroup'
            ServerName           = $env:COMPUTERNAME
            InstanceName         = 'MSSQLSERVER'
            PsDscRunAsCredential = $localAdminCreds

            dependson = "[service]sqlserver"
        }
        SqlServerRole AddDBAToSysAdmin
        {
            Ensure               = 'Present'
            ServerRoleName       = 'sysadmin'
            MembersToInclude     = 'TAMZ\DBA'
            ServerName           = $env:COMPUTERNAME
            InstanceName         = 'MSSQLSERVER'
            PsDscRunAsCredential = $localAdminCreds

            dependson = '[SqlServerLogin]Add_DBAGroup'
        }

        Script AddDataDisks {
            SetScript  = 
@"            
                        New-StoragePool -FriendlyName 'SQLPool' -StorageSubSystemFriendlyName "Windows Storage*" -PhysicalDisks $physicalDisks 
                        New-Volume -StoragePoolFriendlyName SQLPool* -FriendlyName ${datadrivelabel} -FileSystem NTFS -AllocationUnitSize 65536 -DriveLetter ${datadriveLetter} -size ${datadriveSize};
                        New-Volume -StoragePoolFriendlyName SQLPool* -FriendlyName ${logdrivelabel} -FileSystem NTFS -AllocationUnitSize 65536 -DriveLetter ${logdriveLetter} -size ${logdriveSize};
                        New-Volume -StoragePoolFriendlyName SQLPool* -FriendlyName ${tempdbdrivelabel} -FileSystem NTFS -AllocationUnitSize 65536 -DriveLetter ${tempdbdriveLetter} -size ${tempdbdriveSize};
"@
            TestScript = "(Get-StoragePool -FriendlyName SQLPool*).OperationalStatus -eq 'OK'"
            GetScript  = "@{Ensure = if ((Get-StoragePool -FriendlyName SQLPool*).OperationalStatus -eq 'OK') {'Present'} Else {'Absent'}}"
        }
        $physicalDisks = (Get-PhysicalDisk -canpool $true)
        New-StoragePool -FriendlyName 'SQLPool' -StorageSubSystemFriendlyName "Windows Storage*" -PhysicalDisks $physicalDisks 
        New-Volume -StoragePoolFriendlyName SQLPool* -FriendlyName Data -FileSystem NTFS -AllocationUnitSize 65536 -DriveLetter G -size 5GB;
        New-Volume -StoragePoolFriendlyName SQLPool* -FriendlyName Data -FileSystem NTFS -AllocationUnitSize 65536 -DriveLetter F -size 5GB;
        New-Volume -StoragePoolFriendlyName SQLPool* -FriendlyName Data -FileSystem NTFS -AllocationUnitSize 65536 -DriveLetter T -size 5GB;


    }
}



