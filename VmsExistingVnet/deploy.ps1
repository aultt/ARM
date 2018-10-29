$resourceGroupName = 'ClusterTesting2'
$resourceGroupLocation = "East US"
$templateFile = '/Users/troyault/Documents/GitHub/ARM/VMsaddedtoVnetandDomain/templateupdate.json'
$templateParm = '/Users/troyault/Documents/GitHub/ParameterFiles/VMsToNetparameters.json'

Import-Module Az
Enable-AzureRmAlias -Scope CurrentUser
Connect-AzureRmAccount 
Get-AzureRmSubscription -SubscriptionName TAMZ_MS | Select-AzureRmSubscription

#Create or check for existing resource group
$resourceGroup = Get-AzureRmResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
if(!$resourceGroup)
{
    Write-Host "Resource group '$resourceGroupName' does not exist. To create a new resource group, please enter a location.";
    if(!$resourceGroupLocation) {
        $resourceGroupLocation = Read-Host "resourceGroupLocation";
    }
    Write-Host "Creating resource group '$resourceGroupName' in location '$resourceGroupLocation'";
    New-AzureRmResourceGroup -Name $resourceGroupName -Location $resourceGroupLocation
}
else{
    Write-Host "Using existing resource group '$resourceGroupName'";
}

# Start the deployment
    New-AzureRmResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile $templateFile -TemplateParameterFile $templateParm  -Verbose;
