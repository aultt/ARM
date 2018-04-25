Login-AzureRmAccount
Select-AzureRmSubscription -SubscriptionName TAMZ_SandBox

$RG = 'sqlfci06'
$templateFile = 'D:\Users\TroyAult\OneDrive - TAMZ\Git\ARM\FCI\azuredeploy.json'
$templateParm = 'D:\Users\TroyAult\OneDrive - TAMZ\Git\MyParmFiles\FCI.parameters.json' 
New-AzureRmResourceGroup -Name $RG -Location "East US"
New-AzureRmResourceGroupDeployment -Name NewFCI -ResourceGroupName $RG -TemplateFile $templateFile -TemplateParameterFile $templateParm  -Verbose

Remove-AzureRmResourceGroup -Name $RG -Force

