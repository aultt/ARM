Login-AzureRmAccount
Select-AzureRmSubscription -SubscriptionName TAMZ_InternalApps
$RG = 'sqlfci06'

$templateFile = 'C:\Users\troyault\OneDrive - TAMZ\Git\ARM\FCI\azuredeploy.json'
$templateParm = 'C:\Users\troyault\OneDrive - TAMZ\Git\MyParmFiles\FCI.parameters.json' 
New-AzureRmResourceGroup -Name $RG -Location "East US"
New-AzureRmResourceGroupDeployment -Name NewFCI -ResourceGroupName $RG -TemplateFile $templateFile -TemplateParameterFile $templateParm  -Verbose

Remove-AzureRmResourceGroup -Name $RG -Force



