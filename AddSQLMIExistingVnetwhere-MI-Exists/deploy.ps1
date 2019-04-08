$resourceGroupName = 'SQLMIAddDemo'
$resourceGroupLocation = "East US"
$templateFile = 'D:\GitHub\ARM\AddSQLMIExistingVnetwhere-MI-Exists\template.json'
$templateParm = 'D:\ParameterFiles\AddSQLMIExistingVnetwher-MI-Exists.parameters.json'
$subscription = 'TAMZ_MS'
# ii 'D:\ParameterFiles\AddSQLMIExistingVnetwher-MI-Exists.parameters.json'
 
Import-Module Az
Login-AzAccount 
Select-AZSubscription -SubscriptionName $subscription 

#Create or check for existing resource group
$resourceGroup = Get-AZResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
if(!$resourceGroup)
{
    Write-Host "Resource group '$resourceGroupName' does not exist. To create a new resource group, please enter a location.";
    if(!$resourceGroupLocation) {
        $resourceGroupLocation = Read-Host "resourceGroupLocation";
    }
    Write-Host "Creating resource group '$resourceGroupName' in location '$resourceGroupLocation'";
    New-AZResourceGroup -Name $resourceGroupName -Location $resourceGroupLocation
}
else{
    Write-Host "Using existing resource group '$resourceGroupName'";
}

# Start the deployment
New-AZResourceGroupDeployment  -ResourceGroupName $resourceGroupName -TemplateFile $templateFile -TemplateParameterFile $templateParm  -Verbose;
