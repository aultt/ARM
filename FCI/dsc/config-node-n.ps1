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
        [String]$SQLClusterName
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
        
        Script MoveClusterGroups0 {
            SetScript  = 'try {Get-ClusterGroup -ErrorAction SilentlyContinue | Move-ClusterGroup -Node $env:COMPUTERNAME -ErrorAction SilentlyContinue} catch {}'
            TestScript = 'return $false'
            GetScript  = '@{Result = "Moved Cluster Group"}'
            DependsOn  = "[xComputer]DomainJoin"
        }

        xCluster FailoverCluster
        {
            Name                          = $ClusterName
            StaticIPAddress = '10.40.4.102'
            DomainAdministratorCredential = $domainuserCreds
            DependsOn                     = "[Script]MoveClusterGroups0"
        }

        Script CleanSQL
        {
            SetScript = 'C:\SQLServerFull\Setup.exe /Action=Uninstall /FEATURES=SQL,AS,IS,RS /INSTANCENAME=MSSQLSERVER /Q'
            TestScript = '(test-path -Path "C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\DATA\master.mdf") -eq $false'
            GetScript = '@{Ensure = if ((test-path -Path "C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\DATA\master.mdf") -eq $false) {"Present"} Else {"Absent"}}'
            DependsOn = "[xCluster]FailoverCluster"
        }

        xPendingReboot Reboot1
        { 
            Name = "Reboot1"
            DependsOn = "[Script]CleanSQL"
        }

        #xSQLServerFailoverClusterSetup PrepareMSSQLSERVER
        #{
        #    DependsOn = "[xPendingReboot]Reboot1"
        #    Action = "Prepare"
        #    SourcePath = "C:\"
        #    SourceFolder = "SQLServerFull"
        #    UpdateSource = ""
        #    SetupCredential = $domainCreds
        #    Features = $SQLFeatures
        #    InstanceName = $SQLInstance
        #    FailoverClusterNetworkName = $SQLClusterName
        #    SQLSvcAccount = $ServiceCreds
        #}

        #xFirewall SQLFirewall
        #{
        #    Name = "SQL Firewall Rule"
        #    DisplayName = "SQL Firewall Rule"
        #    Ensure = "Present"
        #    Enabled = "True"
        #    Profile = ("Domain", "Private", "Public")
        #    Direction = "Inbound"
        #    RemotePort = "Any"
        #    LocalPort = ("445", "1433", "37000", "37001")
        #    Protocol = "TCP"
        #    Description = "Firewall Rule for SQL"
        #    DependsOn = "[xSQLServerFailoverClusterSetup]PrepareMSSQLSERVER"
        #}

        #xPendingReboot Reboot2
        #{ 
        #    Name = 'Reboot2'
        #    DependsOn = "[xFirewall]SQLFirewall"
        #}

    }
}
