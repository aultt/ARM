
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
        SqlServerRole Add_ServerRole_AdminSqlforBI
        {
            Ensure               = 'Present'
            ServerRoleName       = 'sysadmin'
            Members              = 'TAMZ\DBA'
            ServerName           = $env:COMPUTERNAME
            InstanceName         = 'MSSQLSERVER'
            PsDscRunAsCredential = $localAdminCreds
        }
        
    }
}



