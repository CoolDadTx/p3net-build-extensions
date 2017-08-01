[CmdletBinding()]
param()

# Gets the Julian date
function GetJulianDate
{
	$now = [DateTime]::Now

	return $now.ToString("yy") + $now.DayOfYear.ToString("000")
}

# Finds the revision in the build number
function GetRevision
{
	param(
		[string][Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()] $number
	)
	
    # Split the value by the .
    $tokens = $number.Split('.');

    # In general we want the last one but a Draft build will have a non-number here so find the 
    # last token that is a number
    for ($index = $tokens.Length - 1; $index -ge 0; $index--) {        
        $value = 0
        if ([System.Int32]::TryParse($tokens[$index], [ref] $value)) {
           return $value.ToString()
        }
	};

	throw "Unable to locate revision number"
}

# Generates the attributes for the version files
function GenerateAttributes 
{    
	# Build number is the full build name and we just care about the revision part of it so strip that out
	$revision = GetRevision $buildNumber

	if ([String]::IsNullOrEmpty($build)) { $build = GetJulianDate }

	# Calculate the values we'll need 
	$longVersion = "$major.$minor.$build.$revision"
	$shortVersion = "$major.$minor.0.0"
 
	# Set the final attributes - would like to use a hashtable here but VSTS SDK breaks hashtables...
	$attributes = @{
        "AssemblyProduct" = $product;
        "AssemblyCompany" = $company;
	    "AssemblyCopyright" = "Copyright © $company";
	    "AssemblyTrademark" = $trademark;
	
        "AssemblyVersion" = $shortVersion;
        "AssemblyFileVersion" = $longVersion;
	    "AssemblyInformationalVersion" = $longVersion;
	    "AssemblyConfiguration" = $configuration;
    }

	# Log the attributes
	Write-VstsTaskDebug 'Calculated attributes'
	foreach ($attribute in $attributes.GetEnumerator())
	{    
		Write-VstsTaskDebug "$($attribute.Key) = $($attribute.Value)"        
	}        

	# Publish the version information to TFS
	Write-Host "Product Version = $shortVersion"
	Write-Host "Full Version = $longVersion"
	Set-VstsTaskVariable -Name "Version_Product" -Value $shortVersion
	Set-VstsTaskVariable -Name "Version_Full" -Value $longVersion
	return $attributes
}

# Trims comments from a line
function TrimComments
{
	param(
		[string] $line
	)

	$index = $line.IndexOf("//")
	if ($index -lt 0) { return $line }

	return $line.Substring(0, $index).Trim()
}

# Updates all the files matching the given pattern with the provided attributes
function UpdateVersionFiles 
{
	param(
		[string][Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()] $filePath,
		[string][Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()] $searchPattern,
		[Hashtable] $attributes
	)

	$files = [System.IO.Directory]::GetFiles($filePath, $searchPattern, [System.IO.SearchOption]::AllDirectories) 

	$fileIndex = 0
	$fileCount = $files.Count

	foreach($file in $files)
	{
		Write-VstsTaskVerbose "Updating version information in $file"
		UpdateVersionFile $file $attributes
		$fileIndex += 1
	}    
	Write-VstsTaskVerbose "Finished updating version files"
}

# Updates a file with the attributes specified 
function UpdateVersionFile
{
	param(
		[string][Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()] $filePath,
		[Hashtable] $attributes
	)
	
	#Removes ReadOnly attribute from file
	Set-ItemProperty $filePath -name IsReadOnly -value $false
	
	# Load text into $lines
	$lines = New-Object System.Collections.Generic.List[string]
	$lines.AddRange([System.IO.File]::ReadAllLines($filePath))

	foreach($attribute in $attributes.GetEnumerator())
	{
		# Create a new regular expression        
		$re = "^\[assembly\s*:\s*$($attribute.Key)(Attribute)?\s*\(\s*(`".*`"\s*)?\s*\)\s*\]$"
	
		$foundMatch = $false
		$newValue = '[assembly: ' + $($attribute.Key) + '("' + $($attribute.Value) + '")]'
		
		# Find the matching line, if any
		for ($index = 0; $index -lt $lines.Count; ++$index)
		{
			# Skip comments and blank lines
			$line = TrimComments($lines[$index])
			if ([String]::IsNullOrEmpty($line)) { continue }

			# Does the line match
			if ($line -imatch $re)
			{
				Write-VstsTaskDebug "Replacing $($attribute.Key)"
				$lines[$index] = $newValue
				$foundMatch = $true
			}
		}

		#If line does not exist then add a new line of the attribute and value into file
		if (-not $foundMatch)
		{
			Write-VstsTaskDebug "Adding $($attribute.Key)"
			$lines.Add($newValue)
		}
	}
	[System.IO.File]::WriteAllLines($filePath, $lines.ToArray())
} 

###### Entry Point ########

Trace-VstsEnteringInvocation $MyInvocation

# Get inputs
$product = Get-VstsInput -Name product -Require
$major = Get-VstsInput -Name major -AsInt -Require
$minor = Get-VstsInput -Name minor -AsInt -Require
$company = Get-VstsInput -Name company -Require
$assemblyInfoFilePattern = Get-VstsInput -Name assemblyInfoFilePattern -Require
$build = Get-VstsInput -Name build
$sourcePath = $env:BUILD_SOURCESDIRECTORY
$buildNumber = $env:BUILD_BUILDNUMBER
$trademark = Get-VstsInput -Name trademark
$configuration = Get-VstsInput -Name configuration

try {
    # Generate the attributes based upon the parameters    
    Write-VstsTaskVerbose 'Generating attributes'
    $attributes = GenerateAttributes

    # Enumerate to get all files needed
    Write-VstsTaskVerbose 'Updating files'
    UpdateVersionFiles $sourcePath $assemblyInfoFilePattern $attributes
} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}
