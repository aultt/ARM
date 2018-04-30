configuration ConfigNodeN
{
    param
    (
        [Parameter(Mandatory)]
        [String]$DomainName,
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$domainuserCreds,
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$svcCreds,      
        [Parameter(Mandatory)]
        [String]$ClusterName,
        [Parameter(Mandatory)]
        [String]$SQLClusterName,
        [Parameter(Mandatory)]
        [String]$witnessStorageName,
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$witnessStorageKey,
        [Parameter(Mandatory)]
        [String]$clusterIP,
        
        [Int]$RetryCount = 20,
        [Int]$RetryIntervalSec = 30,
        [Int]$probePort = 37000, 

        [string]$datadriveLetter,
        [string]$datadrivelabel,
        [string]$datadriveSize,
        [string]$logdriveLetter,
        [string]$logdrivelabel,
        [string]$logdriveSize,
        [string]$tempdbdriveLetter,
        [string]$tempdbdrivelabel,
        [string]$tempdbdriveSize,
        [string]$SQLFeatures,
        [string]$SQLInstance,
        [string]$InstallSQLDataDir,
        [string]$InstanceDir ="G:\",
        [string]$SQLUserDBDir = "G:\MSSQL",
        [string]$SQLUserDBLogDir = "L:\MSSQL",
        [string]$SQLTempDBDir = "T:\TEMPDB",
        [string]$SQLTempDBLogDir = "T:\TEMPDB",
        [string]$SQLBackupDir = "G:\BACKUP"
    )

    Import-DscResource -ModuleName xComputerManagement, xActiveDirectory, SQLServerDSC, xPendingReboot, xNetworking,xFailoverCluster

    Node localhost
    {
        # Set LCM to reboot if needed
        LocalConfigurationManager {
            DebugMode = "ForceModuleImport"
            RebootNodeIfNeeded = $true
        }

        WindowsFeature FC 
        {
            Name = "Failover-Clustering"
            Ensure = "Present"
        }
        
        WindowsFeature FailoverClusterTools { 
            Ensure    = "Present" 
            Name      = "RSAT-Clustering-Mgmt"
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

        WindowsFeature FS
        {
            Name = "FS-FileServer"
            Ensure = "Present"
        }

        xWaitForADDomain DscForestWait
        { 
            DomainName = $DomainName 
            DomainUserCredential = $domainuserCreds
            RetryCount = $RetryCount 
            RetryIntervalSec = $RetryIntervalSec 
            DependsOn = "[WindowsFeature]ADPS"
        }

        xComputer DomainJoin
        {
            Name = $env:COMPUTERNAME
            DomainName = $DomainName
            Credential = $domainuserCreds
            DependsOn = "[xWaitForADDomain]DscForestWait"
        }


        Script CleanSQL
        {
           SetScript = 'C:\SQLServerFull\Setup.exe /Action=Uninstall /FEATURES=SQL,AS,IS,RS /INSTANCENAME=MSSQLSERVER /Q'
            TestScript = '(test-path -Path "C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\DATA\master.mdf") -eq $false'
            GetScript = '@{Ensure = if ((test-path -Path "C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\DATA\master.mdf") -eq $false) {"Present"} Else {"Absent"}}'
        }

        xPendingReboot Reboot1
        { 
            Name = "Reboot1"
            DependsOn = "[Script]CleanSQL"
        }
    }
}
