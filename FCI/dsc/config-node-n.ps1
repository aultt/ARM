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
        #[String]$DomainNetbiosName = (Get-NetBIOSName -DomainName $DomainName),
        [Int]$RetryCount = 20,
        [Int]$RetryIntervalSec = 30,
        [string]$SQLFeatures,
        [string]$SQLInstance,
        [String]$SQLClusterName,
        [string]$datadriveLetter = 'G',
        [string]$datadrivelabel = 'Data',
        [string]$datadriveSize = '10GB',
        [string]$logdriveLetter = 'L',
        [string]$logdrivelabel ='Logs',
        [string]$logdriveSize ='5GB'
    )

    Import-DscResource -ModuleName xComputerManagement, xActiveDirectory, xPendingReboot, xNetworking,sqlserverdsc,xfailovercluster

    Node localhost
    {
        # Set LCM to reboot if needed
        LocalConfigurationManager {
            DebugMode = "ForceModuleImport"
            ActionafterReboot = 'ContinueConfiguration'
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
        xWaitForCluster WaitForCluster
        {
            Name             = 'aesql200c'
            RetryIntervalSec = 30
            RetryCount       = 60
            DependsOn        = '[xComputer]DomainJoin','[WindowsFeature]FC' 
        }

        xCluster JoinSecondNodeToCluster
        {
            Name                          = 'aesql200c'
            StaticIPAddress               = '10.30.4.103/24'
            DomainAdministratorCredential = $domainuserCreds
            DependsOn                     = '[xWaitForCluster]WaitForCluster'
        }
        
        Script EnableS2D {
            #SetScript  = "Enable-ClusterS2D -Confirm:0; New-Volume -StoragePoolFriendlyName S2D* -FriendlyName VDisk01 -FileSystem NTFS -DriveLetter ${driveLetter} -UseMaximumSize"
            #SetScript = Enable-ClusterS2D -Confirm:0;New-Volume -StoragePoolFriendlyName S2D* -FriendlyName ${datadrivelable} -FileSystem NTFS -AllocationUnitSize 65536 -DriveLetter ${datadriveLetter} -size ${datadriveSize};
            #latest Run Changes to include all three drives
            SetScript  = 
@"
                            Enable-ClusterS2D -Confirm:0; 
                            New-Volume -StoragePoolFriendlyName S2D* -FriendlyName ${datadrivelabel} -FileSystem NTFS -AllocationUnitSize 65536 -DriveLetter ${datadriveLetter} -size ${datadriveSize};
                            New-Volume -StoragePoolFriendlyName S2D* -FriendlyName ${logdrivelabel} -FileSystem NTFS -AllocationUnitSize 65536 -DriveLetter ${logdriveLetter} -size ${logdriveSize};
                            New-Volume -StoragePoolFriendlyName S2D* -FriendlyName ${tempdbdrivelabel} -FileSystem NTFS -AllocationUnitSize 65536 -DriveLetter ${tempdbdriveLetter} -size ${tempdbdriveSize};
"@
            TestScript = "(Get-StoragePool -FriendlyName S2D*).OperationalStatus -eq 'OK'"
            GetScript  = "@{Ensure = if ((Get-StoragePool -FriendlyName S2D*).OperationalStatus -eq 'OK') {'Present'} Else {'Absent'}}"
            DependsOn  = "[xCluster]JoinSecondNodeToCluster",'[WindowsFeature]FS'
        }
#        Script CleanSQL
#        {
#            SetScript = 'C:\SQLServerFull\Setup.exe /Action=Uninstall /FEATURES=SQL,AS,IS,RS /INSTANCENAME=MSSQLSERVER /Q'
#            TestScript = '(test-path -Path "C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\DATA\master.mdf") -eq $false'
#            GetScript = '@{Ensure = if ((test-path -Path "C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\DATA\master.mdf") -eq $false) {"Present"} Else {"Absent"}}'
#            DependsOn = "[xComputer]DomainJoin"
#        }

#        xPendingReboot Reboot1
#        { 
#            Name = "Reboot1"
#            DependsOn = "[Script]CleanSQL"
#        }
#
#        WindowsFeature 'NetFramework45'
#        {
#            Name   = 'NET-Framework-45-Core'
#            Ensure = 'Present'
#        }
#
#
#        SqlSetup 'InstallNamedInstanceNode2'
#        {
#            Action                     = 'AddNode'
#            ForceReboot                = $false
#            UpdateEnabled              = 'False'
#            SourcePath                 = 'C:\SQLServerFull'
#
#            InstanceName               = 'INST2016'
#            Features                   = 'SQLENGINE'
#
#            SQLSvcAccount              = $svcCreds
#            AgtSvcAccount              = $svcCreds
#
#            FailoverClusterNetworkName = 'TESTCLU01A'
#
#            PsDscRunAsCredential       = $domainuserCreds
#
#            DependsOn                  =  '[WindowsFeature]NetFramework45','[xPendingReboot]Reboot1'
#        }
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
#            DependsOn = "[SqlSetup]InstallNamedInstanceNode2"
#        }

    }
}
