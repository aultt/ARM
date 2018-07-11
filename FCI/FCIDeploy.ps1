Login-AzureRmAccount

Select-AzureRmSubscription -SubscriptionName TAMZ_InternalApps

$RG = 'yourrg'
New-AzureRmResourceGroup -Name $RG -Location "East US"
New-AzureRmResourceGroupDeployment -Name NewFCI -ResourceGroupName $RG -TemplateFile 'C:\Repos\ARM-Templates\FCI\azuredeploy.json' `
 -TemplateParameterFile 'C:\Repos\ARM-Templates\FCI\azuredeploy.parameters.json'


#Remove-AzureRmResourceGroup -Name $RG -Force

