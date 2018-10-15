Import-Module Az
Enable-AzureRmAlias -Scope CurrentUser
Connect-AzureRmAccount
$RG = 'tim-SQLAO-prod'

$templateFile = '/Users/troyault/Documents/GitHub/ARM/AlwaysOn/azuredeploy.json'
$templateParm = '/Users/troyault/Documents/GitHub/ParameterFiles/AlwaysOn.parameters.json'

New-AzureRmResourceGroup -Name $RG -Location "East US"
New-AzureRmResourceGroupDeployment -Name NewSQL -ResourceGroupName $RG -TemplateFile $templateFile -TemplateParameterFile $templateParm  -Verbose

#Remove-AzureRmResourceGroup -Name $RG -Force
#clear-hostg