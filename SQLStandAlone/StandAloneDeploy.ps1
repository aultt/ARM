Import-Module Az
Enable-AzureRmAlias -Scope CurrentUser
Connect-AzureRmAccount 
Get-AzureRmSubscription -SubscriptionName TAMZ_MS | Select-AzureRmSubscription

$RG = 'ClusterTesting'

$templateFile = '/Users/troyault/Documents/GitHub/ARM/SQLStandAlone/azuredeploy.json'
$templateParm = '/Users/troyault/Documents/GitHub/ParameterFiles/StandAloneMSSub.parameters.json'
New-AzureRmResourceGroup -Name $RG -Location "East US"
New-AzureRmResourceGroupDeployment -Name NewSQL -ResourceGroupName $RG -TemplateFile $templateFile -TemplateParameterFile $templateParm  -Verbose

#Remove-AzureRmResourceGroup -Name $RG -Force 
#clear-host 