<#
    .SYNOPSIS
        Autogenerates the allowed sizes for masters and agents and the
		associated storage map.

    .DESCRIPTION
        Autogenerates the allowed sizes for masters and agents and the
		associated storage map.

    .PARAMETER OutFile
        The name of the outputfile (Default is pkg/acsengine/azureconst.go)

    .EXAMPLE
        .\Get-AzureConstants.ps1  -OutFile "pkg/acsengine/azureconst.go"
	.NOTES
		On making any changes to this file, run the following command to update the output file
		.\Get-AzureConstants.ps1  -OutFile "pkg/acsengine/azureconst.go"
#>
[CmdletBinding(DefaultParameterSetName="Standard")]
param(
    [string]
    $OutFile = "pkg/acsengine/azureconst.go"
)

function
Get-AllSizes() {
	$locations = Get-AzureRmLocation | Select-Object -Property Location
	$sizeMap = @{}
	ForEach ($location in $locations) {
		#Write-Output $location.Location
		$sizes = Get-AzureRmVMSize -Location $location.Location
		#Filtered out Basic sizes as Azure Load Balancer does not support Basic SKU
		ForEach ($size in $sizes) {
			if (!$sizeMap.ContainsKey($size.Name) -and !($size.Name.split('_')[0] -eq 'Basic')) {
				$sizeMap.Add($size.Name, $size)
			}	
		}
		#Write-Host "Break for debugging"
		#break
	}
	return $sizeMap
}

#  1. Masters and Agents >= 2 cores
#  2. DCOS Masters >= 2 cores and ephemeral disk >= 100 GB
$MINIMUM_CORES = 2
$DCOS_MASTERS_EPHEMERAL_DISK_MIN = 102400

function 
Get-DcosMasterMap() {
	param(
        [System.Collections.Hashtable]
        $SizeMap
    )

	$masterMap = @{}
	ForEach ($k in ($SizeMap.Keys | Sort-Object)) {
		$size = $SizeMap[$k]
		if ($size.NumberOfCores -ge $MINIMUM_CORES -and 
			$size.ResourceDiskSizeInMB -ge $DCOS_MASTERS_EPHEMERAL_DISK_MIN) {
			$masterMap.Add($size.Name, $size)
		}
	}
	return $masterMap
}

function 
Get-MasterAgentMap() {
	param(
        [System.Collections.Hashtable]
        $SizeMap
    )

	$agentMap = @{}
	ForEach ($k in ($SizeMap.Keys | Sort-Object)) {
		#Write-Output $location.Location
		$size = $SizeMap[$k]
		if ($size.NumberOfCores -ge $MINIMUM_CORES) {
			$agentMap.Add($size.Name, $size)
		}	
	}
	return $agentMap
}

function 
Get-KubernetesAgentMap() {
	param(
        [System.Collections.Hashtable]
        $SizeMap
    )

	$agentMap = @{}
	ForEach ($k in ($SizeMap.Keys | Sort-Object)) {
		#Write-Output $location.Location
		$size = $SizeMap[$k]
		# if ($size.NumberOfCores -ge $MINIMUM_CORES) {
		# 	$agentMap.Add($size.Name, $size)
		# }	
		$agentMap.Add($size.Name, $size)
	}
	return $agentMap
}

function
Get-Locations() {
	$locations = Get-AzureRmLocation | Select-Object -Property Location
	$locationList = @()
	ForEach ($location in $locations) {
		$locationList += $location.Location
	}
	#hard code Azure China Cloud location
	$locationList += "chinanorth"
	$locationList += "chinaeast"
	$locationList += "germanycentral"
	$locationList += "germanynortheast"
	$locationList += "usgoviowa"
	$locationList += "usgovvirginia"
	$locationList += "usgovarizona"
	$locationList += "usgovtexas"
	return $locationList
}

function 
Get-StorageAccountType($sizeName) {
	$capability = $sizeName.Split("_")[1]
	if ($capability.Contains("S") -Or $capability.Contains("s"))
	{
		return "Premium_LRS"
	}
	else
	{
		return "Standard_LRS"
	}
}

function
Get-FileContents() {
	param(
		[System.Collections.Hashtable]
        $DCOSMasterMap,
		[System.Collections.Hashtable]
        $MasterAgentMap,
		[System.Collections.Hashtable]
        $SizeMap,
		[System.Collections.ArrayList]
        $Locations
    )
	
	$text = "package acsengine"
	$text += @"


// AUTOGENERATED FILE - last generated $(Get-Date -format 'u')

// AzureLocations provides all azure regions in prod.
// Related powershell to refresh this list:
//   Get-AzureRmLocation | Select-Object -Property Location
var AzureLocations = []string{

"@
	ForEach ($location in ($Locations | Sort-Object)) {
		$text += '	"' + $location + '"' + ",`r`n"
	}
	$text += @"
}

// GetDCOSMasterAllowedSizes returns the master allowed sizes
func GetDCOSMasterAllowedSizes() string{
    return ``      "allowedValues": [

"@
    $first = $TRUE
	ForEach ($k in ($DCOSMasterMap.Keys | Sort-Object)) {
		if ($first -eq $TRUE) 
		{
			$first = $FALSE
		}
		else
		{
			$text += ",`r`n"
		}
		$text += '        "' + $DCOSMasterMap.Item($k).Name + '"'
	}
	$text += @"

     ],
``
}

// GetMasterAgentAllowedSizes returns the agent allowed sizes
func GetMasterAgentAllowedSizes() string {
    return ``      "allowedValues": [

"@
	$first = $TRUE
	ForEach ($k in ($MasterAgentMap.Keys | Sort-Object)) {
		if ($first -eq $TRUE) 
		{
			$first = $FALSE
		}
		else
		{
			$text += ",`r`n"
		}
		$text += '        "' + $MasterAgentMap.Item($k).Name + '"'
	}
	$text += @"

     ],
``
}

// GetKubernetesAgentAllowedSizes returns the allowed sizes for Kubernetes agents
func GetKubernetesAgentAllowedSizes() string {
    return ``      "allowedValues": [

"@
	$first = $TRUE
	ForEach ($k in ($KubernetesAgentMap.Keys | Sort-Object)) {
		if ($first -eq $TRUE) 
		{
			$first = $FALSE
		}
		else
		{
			$text += ",`r`n"
		}
		$text += '        "' + $KubernetesAgentMap.Item($k).Name + '"'
	}
	$text += @"

     ],
``
}

// GetSizeMap returns the size / storage map
func GetSizeMap() string{
    return ``    "vmSizesMap": {

"@

	# merge the maps
	$mergedMap = @{}
	ForEach ($k in $MasterAgentMap.Keys) {
		$size = $MasterAgentMap.Item($k)
		if (!$mergedMap.ContainsKey($k)) {
			$mergedMap.Add($size.Name, $size)
		}
	}
	ForEach ($k in $DCOSMasterMap.Keys) {
		$size = $DCOSMasterMap.Item($k)
		if (!$mergedMap.ContainsKey($k)) {
			$mergedMap.Add($size.Name, $size)
		}
	}

	$first = $TRUE
	ForEach ($k in ($mergedMap.Keys | Sort-Object)) {
		$size = $mergedMap.Item($k)
		if ($first -eq $TRUE) 
		{
			$first = $FALSE
		}
		else
		{
			$text += ",`r`n"
		}
		$text += '      "' + $size.Name + '": {' + "`r`n"
		$storageAccountType = Get-StorageAccountType($size.Name)
		$text += '        "storageAccountType": "' + $storageAccountType + '"' + "`r`n"
		$text += '      }'
	}
	$text += @"

    }	
``
}

// GetClassicAllowedSizes returns the classic allowed sizes
func GetClassicAllowedSizes() string {
    return ``      "allowedValues": [

"@
	$first = $TRUE
	ForEach ($k in ($SizeMap.Keys | Sort-Object)) {
		if ($first -eq $TRUE) 
		{
			$first = $FALSE
		}
		else
		{
			$text += ",`r`n"
		}
		$text += '        "' + $SizeMap.Item($k).Name + '"'
	}
	$text += @"

     ],
``
}

// GetClassicSizeMap returns the size / storage map
func GetClassicSizeMap() string{
    return ``    "vmSizesMap": {

"@

	$first = $TRUE
	ForEach ($k in ($SizeMap.Keys | Sort-Object)) {
		$size = $SizeMap.Item($k)
		if ($first -eq $TRUE) 
		{
			$first = $FALSE
		}
		else
		{
			$text += ",`r`n"
		}
		$text += '      "' + $size.Name + '": {' + "`r`n"
		$storageAccountType = Get-StorageAccountType($size.Name)
		$text += '        "storageAccountType": "' + $storageAccountType + '"' + "`r`n"
		$text += '      }'
	}
	$text += @"

    }	
``
}
"@
	return $text
}

try
{
	$allSizes = Get-AllSizes
	$dcosMasterMap = Get-DCOSMasterMap -SizeMap $allSizes
	$masterAgentMap = Get-MasterAgentMap -SizeMap $allSizes
	$kubernetesAgentMap = Get-KubernetesAgentMap -SizeMap $allSizes
	$locations = Get-Locations
	$text = Get-FileContents -DCOSMasterMap $dcosMasterMap -MasterAgentMap $masterAgentMap -KubernetesAgentMap $kubernetesAgentMap -SizeMap $allSizes -Locations $locations
	$text | Out-File $OutFile
	(Get-Content $OutFile) -replace "`0", "" | Set-Content $OutFile
	gofmt -w $OutFile
}
catch
{
	Write-Error $_
}



