Login-AzureRmAccount
Select-AzureRmSubscription -SubscriptionName TAMZ_InternalApps
$RG = 'sqlRG'

$templateFile = 'C:\Users\troyault\OneDrive - TAMZ\Git\ARM\SQLStandAlone\azuredeploy.json'
$templateParm = 'C:\Users\troyault\OneDrive - TAMZ\Git\MyParmFiles\StandAlone.parameters.json' 
New-AzureRmResourceGroup -Name $RG -Location "East US"
New-AzureRmResourceGroupDeployment -Name NewSQL -ResourceGroupName $RG -TemplateFile $templateFile -TemplateParameterFile $templateParm  -Verbose

Remove-AzureRmResourceGroup -Name $RG -Force
clear-host
