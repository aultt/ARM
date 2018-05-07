Login-AzureRmAccount
Select-AzureRmSubscription -SubscriptionName TAMZ_SandBox

$RG = 'sqlfci06'
$templateFile = 'C:\Users\troyault\OneDrive - TAMZ\Git\ARM\dev\FCI\azuredeploy.json'
$templateParm = 'C:\Users\troyault\OneDrive - TAMZ\Git\MyParmFiles\FCI.parameters.json' 
New-AzureRmResourceGroup -Name $RG -Location "East US"
New-AzureRmResourceGroupDeployment -Name NewFCI -ResourceGroupName $RG -TemplateFile $templateFile -TemplateParameterFile $templateParm  -Verbose

Remove-AzureRmResourceGroup -Name $RG -Force



