
configuration ConfigNode1
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
        [String]$vmNamePrefix,

        [Parameter(Mandatory)]
        [Int]$vmCount,

        [Parameter(Mandatory)]
        [Int]$vmDiskSize,

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
        [string]$InstanceDir ="${datadriveLetter}:\",
        [string]$SQLUserDBDir = "${datadriveLetter}:\${datadrivelabel}",
        [string]$SQLUserDBLogDir = "${logdriveLetter}:\${logdrivelabel}",
        [string]$SQLTempDBDir = "${tempdbdriveLetter}:\${tempdbdrivelabel}",
        [string]$SQLTempDBLogDir = "${tempdbdriveLetter}:\${tempdbdrivelabel}",
        [string]$SQLBackupDir = "${datadriveLetter}:\BACKUP"
    )

    Import-DscResource -ModuleName xComputerManagement, xFailOverCluster, xActiveDirectory, xSOFS, SQLServerDSC, xPendingReboot, xNetworking
    [string[]]$SQLSysAdminAccounts = "${DomainName}\Domain Admins"

    Node localhost
    {
        # Set LCM to reboot if needed
        LocalConfigurationManager {
            DebugMode          = "ForceModuleImport"
            RebootNodeIfNeeded = $true
        }
        
        WindowsFeature FC {
            Name   = "Failover-Clustering"
            Ensure = "Present"
        }

        WindowsFeature FailoverClusterTools { 
            Ensure    = "Present" 
            Name      = "RSAT-Clustering-Mgmt"
            DependsOn = "[WindowsFeature]FC"
        } 

        WindowsFeature FCPS {
            Name   = "RSAT-Clustering-PowerShell"
            Ensure = "Present"
        }

        WindowsFeature ADPS {
            Name   = "RSAT-AD-PowerShell"
            Ensure = "Present"
        }

        WindowsFeature FS {
            Name   = "FS-FileServer"
            Ensure = "Present"
        }

        xWaitForADDomain DscForestWait 
        { 
            DomainName       = $DomainName 
            DomainUserCredential= $domainuserCreds
            RetryCount       = $RetryCount 
            RetryIntervalSec = $RetryIntervalSec 
            DependsOn        = "[WindowsFeature]ADPS"
        }
        
        xComputer DomainJoin
        {
            Name       = $env:COMPUTERNAME
            DomainName = $DomainName
            Credential = $domainuserCreds
            DependsOn  = "[xWaitForADDomain]DscForestWait"
        }
        
        Script CleanSQL {
            SetScript  = 'C:\SQLServerFull\Setup.exe /Action=Uninstall /FEATURES=SQL,AS,RS,IS /INSTANCENAME=MSSQLSERVER /Q'
            TestScript = '(test-path -Path "C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\DATA\master.mdf") -eq $false'
            GetScript  = '@{Ensure = if ((test-path -Path "C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\DATA\master.mdf") -eq $false) {"Present"} Else {"Absent"}}'
        }
        xPendingReboot Reboot1
        { 
            Name      = 'Reboot1'
            DependsOn = "[Script]CleanSQL"
        }
        xCluster FailoverCluster
        {
            Name                          = $ClusterName
            StaticIPAddress = '10.40.4.102'
            DomainAdministratorCredential = $domainuserCreds
            DependsOn                     = "[xPendingReboot]Reboot1"
        }

        Script CloudWitness {
            SetScript  = "Set-ClusterQuorum -CloudWitness -AccountName ${witnessStorageName} -AccessKey $($witnessStorageKey.GetNetworkCredential().Password)"
            TestScript = "(Get-ClusterQuorum).QuorumResource.Name -eq 'Cloud Witness'"
            GetScript  = "@{Ensure = if ((Get-ClusterQuorum).QuorumResource.Name -eq 'Cloud Witness') {'Present'} else {'Absent'}}"
            DependsOn  = "[xCluster]FailoverCluster"
        }

        Script IncreaseClusterTimeouts {
            SetScript  = "(Get-Cluster).SameSubnetDelay = 2000; (Get-Cluster).SameSubnetThreshold = 15; (Get-Cluster).CrossSubnetDelay = 3000; (Get-Cluster).CrossSubnetThreshold = 15"
            TestScript = "(Get-Cluster).SameSubnetDelay -eq 2000 -and (Get-Cluster).SameSubnetThreshold -eq 15 -and (Get-Cluster).CrossSubnetDelay -eq 3000 -and (Get-Cluster).CrossSubnetThreshold -eq 15"
            GetScript  = "@{Ensure = if ((Get-Cluster).SameSubnetDelay -eq 2000 -and (Get-Cluster).SameSubnetThreshold -eq 15 -and (Get-Cluster).CrossSubnetDelay -eq 3000 -and (Get-Cluster).CrossSubnetThreshold -eq 15) {'Present'} else {'Absent'}}"
            DependsOn  = "[Script]CloudWitness"
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
            DependsOn  = "[Script]CloudWitness"
        }
        
        WindowsFeature 'NetFramework45'
        {
            Name   = 'NET-Framework-45-Core'
            Ensure = 'Present'
            DependsOn  = '[Script]EnableS2D'
        }
        
       # SQLSetup FCISQLNode1
       # {
       #     Action                     = 'InstallFailoverCluster'
       #     ForceReboot                = $true
       #     UpdateEnabled              = $false
       #     SourcePath                 = 'c:\SQLServerFull'
       # 
       #     InstanceName               = $SQLInstance
       #     Features                   = $SQLFeatures
       # 
       #     InstallSharedDir           = 'C:\Program Files\Microsoft SQL Server'
       #     InstallSharedWOWDir        = 'C:\Program Files (x86)\Microsoft SQL Server'
       #     InstanceDir                = $InstanceDir
       # 
       #     SQLCollation               = $SQLCollation
       #     SQLSvcAccount              = $svcCreds
       #     AgtSvcAccount              = $svcCreds
       #     SQLSysAdminAccounts        = $SQLSysAdminAccounts
       #
       #     InstallSQLDataDir          = $InstallSQLDataDir
       #     SQLUserDBDir               = $SQLUserDBDir
       #     SQLUserDBLogDir            = $SQLUserDBLogDir
       #     SQLTempDBDir               = $SQLTempDBDir
       #     SQLTempDBLogDir            = $SQLTempDBLogDir
       #     SQLBackupDir               = $SQLBackupDir
       # 
       #     FailoverClusterNetworkName = $SQLClusterName
       #     FailoverClusterIPAddress   = $clusterIP
       #     FailoverClusterGroupName   = $SQLClusterName
       # 
       #     PsDscRunAsCredential       = $domainuserCreds
       # 
        #    DependsOn                  = '[WindowsFeature]NetFramework45', '[Script]CleanSQL','[Script]EnableS2D'
        #}
        #xPendingReboot Reboot2
        #{ 
        #    Name      = 'Reboot2'
        #    DependsOn = "[SQLSetup]FCISQLNode1"
        #}

        #Script FixProbe {
        #    SetScript  = "Get-ClusterResource -Name 'SQL IP*' | Set-ClusterParameter -Multiple @{Address=${clusterIP};ProbePort=${ProbePort};SubnetMask='255.255.255.255';Network='Cluster Network 1';EnableDhcp=0} -ErrorAction SilentlyContinue | out-null;Get-ClusterGroup -Name 'SQL Server*' -ErrorAction SilentlyContinue | Move-ClusterGroup -ErrorAction SilentlyContinue"
        #    TestScript = "(Get-ClusterResource -name 'SQL IP*' | Get-ClusterParameter -Name ProbePort).Value -eq  ${probePort}"
        #    GetScript  = '@{Result = "Moved Cluster Group"}'
        #    DependsOn  = "[SQLSetup]FCISQLNode1"
        #}
    }
}



