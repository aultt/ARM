$resourceGroupName = 'StandAlone2008Testing'
$resourceGroupLocation = "East US"
$templateFile = 'E:\GitLocal\ARM\SQLStandAlone2008ExistingVNet\azuredeploy.json'
$templateParm = 'E:\ParameterFiles\StandAlone2008ExistingVnet.parameters.json'
##ii 'E:\ParameterFiles\StandAlone2008ExistingVnet.parameters.json'

Import-Module Az
Login-AzAccount
Select-AzSubscription -SubscriptionName TAMZ_MS

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


