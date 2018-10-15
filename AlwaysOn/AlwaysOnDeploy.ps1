Login-AzureRmAccount
Select-AzureRmSubscription -SubscriptionName TAMZ_MS
$RG = 'tim-SQLAO-prod'

$templateFile = 'D:\Users\troyault\OneDrive - TAMZ\Git\ARM\AlwaysOn\azuredeploy.json'
$templateParm = 'D:\Users\troyault\OneDrive - TAMZ\Git\MyParmFiles\AlwaysOn.parameters.json'

New-AzureRmResourceGroup -Name $RG -Location "East US"
New-AzureRmResourceGroupDeployment -Name NewSQL -ResourceGroupName $RG -TemplateFile $templateFile -TemplateParameterFile $templateParm  -Verbose

#Remove-AzureRmResourceGroup -Name $RG -Force
#clear-host