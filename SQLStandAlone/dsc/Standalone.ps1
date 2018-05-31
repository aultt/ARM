
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

        sqlsetup  'Default'
        {
            InstanceName = 'MSSQLSERVER'
            Features             = 'SQLENGINE'
            SourcePath = 'C:\SQLServerFull'
            InstallSharedDir           = 'C:\Program Files\Microsoft SQL Server'
            InstallSharedWOWDir        = 'C:\Program Files (x86)\Microsoft SQL Server'
            InstanceDir                = 'C:\Program Files\Microsoft SQL Server'
            
            PsDscRunAsCredential = $localAdminCreds
            dependson = '[xPendingReboot]Reboot1'
        }

        SqlServerLogin Add_DBAGroup
        {
            Ensure               = 'Present'
            Name                 = 'TAMZ\DBA'
            LoginType            = 'WindowsGroup'
            ServerName           = $env:COMPUTERNAME
            InstanceName         = 'MSSQLSERVER'
            PsDscRunAsCredential = $localAdminCreds

            dependson = '[sqlsetup]Default'
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

    }
}



