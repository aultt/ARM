#
# Copyright="ï¿½ Microsoft Corporation. All rights reserved."
#

configuration PrepareAlwaysOnSqlServer
{
    param
    (
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$SQLServicecreds,

        [Parameter(Mandatory)]
        [String]$SqlAlwaysOnEndpointName,

        [UInt32]$DatabaseEnginePort1 = 1433,
        
        [String]$DomainNetbiosName=(Get-NetBIOSName -DomainName $DomainName),

        [Int]$RetryCount=20,
        [Int]$RetryIntervalSec=30
    )

    Import-DscResource -ModuleName xComputerManagement,CDisk,xActiveDirectory,XDisk,xSql, xSQLServer, xSQLps,xNetworking
    [System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ($Admincreds.UserName, $Admincreds.Password)
    [System.Management.Automation.PSCredential]$DomainFQDNCreds = New-Object System.Management.Automation.PSCredential ($Admincreds.UserName, $Admincreds.Password)
    [System.Management.Automation.PSCredential]$SQLCreds = New-Object System.Management.Automation.PSCredential ($SQLServicecreds.UserName, $SQLServicecreds.Password)

    WaitForSqlSetup

    Node localhost
    {
        xWaitforDisk Disk2
        {
             DiskNumber = 2
             RetryIntervalSec =$RetryIntervalSec
             RetryCount = $RetryCount
        }

        cDiskNoRestart DataDisk
        {
            DiskNumber = 2
            DriveLetter = "F"
        }

        xWaitforDisk Disk3
        {
             DiskNumber = 3
             RetryIntervalSec =$RetryIntervalSec
             RetryCount = $RetryCount
        }

        cDiskNoRestart LogDisk
        {
            DiskNumber = 3
            DriveLetter = "G"
        }

        WindowsFeature FC
        {
            Name = "Failover-Clustering"
            Ensure = "Present"
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

       # xWaitForADDomain DscForestWait 
       # { 
       #     DomainName = $DomainName 
       #     DomainUserCredential= $DomainCreds
       #     RetryCount = $RetryCount 
       #     RetryIntervalSec = $RetryIntervalSec 
       # }

        xComputer DomainJoin
        {
            Name = $env:COMPUTERNAME
            DomainName = $DomainName
            Credential = $DomainCreds
        }

        xFirewall DatabaseEngineFirewallRule1
        {
            Direction = "Inbound"
            Name = "SQL-Server-Database-Engine-TCP-In-1"
            DisplayName = "SQL Server Database Engine (TCP-In)"
            Description = "Inbound rule for SQL Server to allow TCP traffic for the Database Engine."
            DisplayGroup = "SQL Server"
            State = "Enabled"
            Access = "Allow"
            Protocol = "TCP"
            LocalPort = $DatabaseEnginePort1 -as [String]
            Ensure = "Present"
        }

        xFirewall DatabaseMirroringFirewallRule
        {
            Direction = "Inbound"
            Name = "SQL-Server-Database-Mirroring-TCP-In"
            DisplayName = "SQL Server Database Mirroring (TCP-In)"
            Description = "Inbound rule for SQL Server to allow TCP traffic for the Database Mirroring."
            DisplayGroup = "SQL Server"
            State = "Enabled"
            Access = "Allow"
            Protocol = "TCP"
            LocalPort = "5022"
            Ensure = "Present"
        }

        xFirewall ListenerFirewallRule1
        {
            Direction = "Inbound"
            Name = "SQL-Server-Availability-Group-Listener-TCP-In-1"
            DisplayName = "SQL Server Availability Group Listener (TCP-In)"
            Description = "Inbound rule for SQL Server to allow TCP traffic for the Availability Group listener."
            DisplayGroup = "SQL Server"
            State = "Enabled"
            Access = "Allow"
            Protocol = "TCP"
            LocalPort = "59999"
            Ensure = "Present"
        }

        xSqlLogin AddDomainAdminAccountToSysadminServerRole
        {
            Name = $DomainCreds.UserName
            LoginType = "WindowsUser"
            ServerRoles = "sysadmin"
            Enabled = $true
            Credential = $Admincreds
        }

        #xADUser CreateSqlServerServiceAccount
        #{
        #    DomainAdministratorCredential = $DomainCreds
        #    DomainName = $DomainName
        #    UserName = $SQLServicecreds.UserName
        #    Password = $SQLServicecreds
        #    Ensure = "Present"
        #    DependsOn = "[xSqlLogin]AddDomainAdminAccountToSysadminServerRole"
        #}

        xSqlLogin AddSqlServerServiceAccountToSysadminServerRole
        {
            Name = $SQLCreds.UserName
            LoginType = "WindowsUser"
            ServerRoles = "sysadmin"
            Enabled = $true
            Credential = $Admincreds
            #DependsOn = "[xADUser]CreateSqlServerServiceAccount"
        }

        xSqlServer ConfigureSqlServerWithAlwaysOn
        {
            InstanceName = $env:COMPUTERNAME
            SqlAdministratorCredential = $Admincreds
            ServiceCredential = $SQLCreds
            MaxDegreeOfParallelism = 1
            FilePath = "F:\DATA"
            LogPath = "G:\LOG"
            DomainAdministratorCredential = $DomainFQDNCreds
            DependsOn = "[xSqlLogin]AddSqlServerServiceAccountToSysadminServerRole"
        }

        LocalConfigurationManager 
        {
            RebootNodeIfNeeded = $True
        }

    }
}

function Get-NetBIOSName
{ 
    [OutputType([string])]
    param(
        [string]$DomainName
    )

    if ($DomainName.Contains('.')) {
        $length=$DomainName.IndexOf('.')
        if ( $length -ge 16) {
            $length=15
        }
        return $DomainName.Substring(0,$length)
    }
    else {
        if ($DomainName.Length -gt 15) {
            return $DomainName.Substring(0,15)
        }
        else {
            return $DomainName
        }
    }
}

function WaitForSqlSetup
{
    # Wait for SQL Server Setup to finish before proceeding.
    while ($true)
    {
        try
        {
            Get-ScheduledTaskInfo "\ConfigureSqlImageTasks\RunConfigureImage" -ErrorAction Stop
            Start-Sleep -Seconds 5
        }
        catch
        {
            break
        }
    }
}
$ConfigData = @{
    AllNodes = @(
    @{
        NodeName = 'localhost'
        PSDscAllowPlainTextPassword = $true
    }
    )
}

#$AdminCreds = Get-Credential
#$SvcCreds = Get-Credential
 PrepareAlwaysOnSqlServer -DomainName tamz.local -Admincreds $AdminCreds -SQLServicecreds $SvcCreds -SqlAlwaysOnEndpointName HADREndpoint -Verbose -ConfigurationData $ConfigData -OutputPath C:\Packages\Plugins\Microsoft.Powershell.DSC\2.77.0.0\DSCWork\prepare-sql-alwayson-server.ps1.0\PrepareAlwaysOnSqlServer 
 Start-DscConfiguration -wait -Force -Verbose -Path C:\Packages\Plugins\Microsoft.Powershell.DSC\2.77.0.0\DSCWork\prepare-sql-alwayson-server.ps1.0\PrepareAlwaysOnSqlServer
