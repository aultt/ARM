
configuration StandAlone
{
    param
    (
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$domainuserCreds,
        
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
        
        xWaitForADDomain DscForestWait 
        { 
            DomainName       = $DomainName 
            DomainUserCredential= $domainuserCreds
            RetryCount       = $RetryCount 
            RetryIntervalSec = $RetryIntervalSec 
        }
        
        xComputer DomainJoin
        {
            Name       = $env:COMPUTERNAME
            DomainName = $DomainName
            Credential = $domainuserCreds
            DependsOn  = "[xWaitForADDomain]DscForestWait"
        }
        
    
#        SqlSetup 'InstallNamedInstanceNode1-INST2016'
#        {
#            Action                     = 'InstallFailoverCluster'
#            ForceReboot                = $false
#            UpdateEnabled              = 'False'
#            SourcePath                 = 'C:\SQLServerFull'
#
#            InstanceName               = 'INST2016'
#            Features                   = 'SQLENGINE'
#
#            InstallSharedDir           = 'C:\Program Files\Microsoft SQL Server'
#            InstallSharedWOWDir        = 'C:\Program Files (x86)\Microsoft SQL Server'
#            InstanceDir                = 'C:\Program Files\Microsoft SQL Server'
#
#            #SQLCollation               = 'Finnish_Swedish_CI_AS'
#            SQLSvcAccount              = $svcCreds
#            AgtSvcAccount              = $svcCreds
#            SQLSysAdminAccounts        = 'TAMZ\DBA'
#
#            # Drive D: must be a shared disk.
#            InstallSQLDataDir          = 'G:\MSSQL\Data'
#            SQLUserDBDir               = 'G:\MSSQL\Data'
#            SQLUserDBLogDir            = 'G:\MSSQL\Log'
#            SQLTempDBDir               = 'G:\MSSQL\Temp'
#            SQLTempDBLogDir            = 'G:\MSSQL\Temp'
#            SQLBackupDir               = 'G:\MSSQL\Backup'
#
#            FailoverClusterNetworkName = 'TESTCLU01A'
#            FailoverClusterIPAddress   = '10.30.4.102'
#            FailoverClusterGroupName   = 'TESTCLU01A'
#
#            PsDscRunAsCredential       = $domainuserCreds
#
#            DependsOn                  = '[Script]MoveClusterGroups3'
#        }
#
#        xFirewall SQLFirewall
#        {
#            Name = "SQL Firewall Rule"
#            DisplayName = "SQL Firewall Rule"
#            Ensure = "Present"
#            Enabled = "True"
#            Profile = ("Domain", "Private", "Public")
#            Direction = "Inbound"
#            RemotePort = "Any"
#            LocalPort = ("445", "1433", "37000", "37001")
#            Protocol = "TCP"
#            Description = "Firewall Rule for SQL"
#            DependsOn = "[SqlSetup]InstallNamedInstanceNode1-INST2016"
#        }
    }
}



