$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()

function Invoke-Test {
	param(
		[Parameter(Mandatory = $true)]
		[string] $Name,

		[Parameter(Mandatory = $true)]
		[scriptblock] $Test
	)

	try {
		& $Test
		Write-Host "[PASS] $Name"
	}
	catch {
		$failures.Add("$Name - $($_.Exception.Message)")
		Write-Host "[FAIL] $Name"
		Write-Host "       $($_.Exception.Message)"
	}
}

function Assert-True {
	param(
		[Parameter(Mandatory = $true)]
		[bool] $Condition,

		[Parameter(Mandatory = $true)]
		[string] $Message
	)

	if (-not $Condition) {
		throw $Message
	}
}

function Assert-Equal {
	param(
		[AllowNull()]
		$Actual,

		[AllowNull()]
		$Expected,

		[Parameter(Mandatory = $true)]
		[string] $Message
	)

	if ($Actual -ne $Expected) {
		throw "$Message Expected '$Expected', got '$Actual'."
	}
}

function Assert-Match {
	param(
		[AllowNull()]
		[string] $Actual,

		[Parameter(Mandatory = $true)]
		[string] $Pattern,

		[Parameter(Mandatory = $true)]
		[string] $Message
	)

	if ($Actual -notmatch $Pattern) {
		throw "$Message '$Actual' did not match '$Pattern'."
	}
}

function Get-Nuspec {
	[xml] (Get-Content -Raw -Path (Join-Path $repoRoot 'duo-auth-proxy.nuspec'))
}

Invoke-Test 'nuspec has required package metadata' {
	$nuspec = Get-Nuspec
	$namespace = New-Object System.Xml.XmlNamespaceManager($nuspec.NameTable)
	$namespace.AddNamespace('nuspec', 'http://schemas.microsoft.com/packaging/2015/06/nuspec.xsd')

	Assert-Equal ($nuspec.SelectSingleNode('/nuspec:package/nuspec:metadata/nuspec:id', $namespace).InnerText) 'duo-auth-proxy' 'Package id mismatch.'
	Assert-Match ($nuspec.SelectSingleNode('/nuspec:package/nuspec:metadata/nuspec:version', $namespace).InnerText) '^\d+\.\d+\.\d+$' 'Package version is not SemVer-like.'
	Assert-True ([bool] $nuspec.SelectSingleNode('/nuspec:package/nuspec:files/nuspec:file[@src="tools\**" and @target="tools"]', $namespace)) 'Nuspec must include the tools folder.'
}

Invoke-Test 'install script version, URL, checksum, and nupkg stay aligned' {
	$nuspec = Get-Nuspec
	$namespace = New-Object System.Xml.XmlNamespaceManager($nuspec.NameTable)
	$namespace.AddNamespace('nuspec', 'http://schemas.microsoft.com/packaging/2015/06/nuspec.xsd')
	$version = $nuspec.SelectSingleNode('/nuspec:package/nuspec:metadata/nuspec:version', $namespace).InnerText
	$installScript = Get-Content -Raw -Path (Join-Path $repoRoot 'tools/chocolateyinstall.ps1')
	$packagePath = Join-Path $repoRoot "packages/duo-auth-proxy.$version.nupkg"

	Assert-Match $installScript "duoauthproxy-$([regex]::Escape($version))\.exe" 'Installer URL must match nuspec version.'
	Assert-Match $installScript "checksumType\s*=\s*'sha256'" 'Install script must verify the installer with SHA-256.'
	Assert-Match $installScript "checksum\s*=\s*'[a-fA-F0-9]{64}'" 'Install script must contain a 64-character SHA-256 checksum.'
	Assert-True (Test-Path $packagePath) "Expected built package at $packagePath."
}

Invoke-Test 'current nupkg contains Chocolatey install assets' {
	$nuspec = Get-Nuspec
	$namespace = New-Object System.Xml.XmlNamespaceManager($nuspec.NameTable)
	$namespace.AddNamespace('nuspec', 'http://schemas.microsoft.com/packaging/2015/06/nuspec.xsd')
	$version = $nuspec.SelectSingleNode('/nuspec:package/nuspec:metadata/nuspec:version', $namespace).InnerText
	$packagePath = Join-Path $repoRoot "packages/duo-auth-proxy.$version.nupkg"

	Add-Type -AssemblyName System.IO.Compression.FileSystem
	$archive = [System.IO.Compression.ZipFile]::OpenRead($packagePath)
	try {
		$entries = $archive.Entries.FullName
		Assert-True ($entries -contains 'duo-auth-proxy.nuspec') 'Package archive does not include duo-auth-proxy.nuspec.'
		Assert-True ($entries -contains 'tools/chocolateyinstall.ps1') 'Package archive does not include chocolateyinstall.ps1.'
		Assert-True ($entries -contains 'tools/chocolateyuninstall.ps1') 'Package archive does not include chocolateyuninstall.ps1.'
		Assert-True ($entries -contains 'tools/.skipAutoUninstall') 'Package archive does not include .skipAutoUninstall.'
	}
	finally {
		$archive.Dispose()
	}
}

Invoke-Test 'install script calls Chocolatey with expected package arguments' {
	$script:installCall = $null
	$env:ChocolateyPackageName = 'duo-auth-proxy'

	function Install-ChocolateyPackage {
		param(
			[string] $packageName,
			[string] $unzipLocation,
			[string] $fileType,
			[string] $url,
			[string] $softwareName,
			[string] $checksum,
			[string] $checksumType,
			[string] $silentArgs,
			[int[]] $validExitCodes
		)

		$script:installCall = $PSBoundParameters
	}

	. (Join-Path $repoRoot 'tools/chocolateyinstall.ps1')

	Assert-Equal $script:installCall.packageName 'duo-auth-proxy' 'Install packageName mismatch.'
	Assert-Equal $script:installCall.fileType 'exe' 'Install fileType mismatch.'
	Assert-Equal $script:installCall.softwareName 'Duo Security Authentication Proxy*' 'Install softwareName mismatch.'
	Assert-Equal $script:installCall.silentArgs '/S' 'Install silent args mismatch.'
	Assert-Equal $script:installCall.checksumType 'sha256' 'Install checksum type mismatch.'
	Assert-Match $script:installCall.url '^https://dl\.duosecurity\.com/duoauthproxy-\d+\.\d+\.\d+\.exe$' 'Install URL mismatch.'
	Assert-True (($script:installCall.validExitCodes -join ',') -eq '0,3010,1641') 'Install valid exit codes mismatch.'
}

Invoke-Test 'install script rejects Windows builds below 10.0.14393' {
	function Install-ChocolateyPackage {
		param(
			[string] $packageName,
			[string] $unzipLocation,
			[string] $fileType,
			[string] $url,
			[string] $softwareName,
			[string] $checksum,
			[string] $checksumType,
			[string] $silentArgs,
			[int[]] $validExitCodes
		)
	}

	. (Join-Path $repoRoot 'tools/chocolateyinstall.ps1')

	Assert-True (-not (Test-DuoAuthProxySupportedOS -Version ([version] '6.3.9600'))) 'Windows Server 2012 R2 should be rejected.'
	Assert-True (-not (Test-DuoAuthProxySupportedOS -Version ([version] '10.0.14392'))) 'Build 14392 should be rejected.'
	Assert-True (Test-DuoAuthProxySupportedOS -Version ([version] '10.0.14393')) 'Build 14393 should be accepted.'
	Assert-True (Test-DuoAuthProxySupportedOS -Version ([version] '10.0.17763')) 'Newer Windows Server builds should be accepted.'
}

Invoke-Test 'uninstall script uses registry uninstall string and Chocolatey uninstall helper' {
	$script:uninstallCall = $null
	$env:ChocolateyPackageName = 'duo-auth-proxy'

	function Get-ItemProperty {
		param(
			[string] $Path
		)

		Assert-Equal $Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DuoAuthProxy' 'Uninstall registry key mismatch.'
		return [pscustomobject] @{
			UninstallString = 'C:\Program Files\Duo Security Authentication Proxy\uninstall.exe'
		}
	}

	function Uninstall-ChocolateyPackage {
		param(
			[string] $packageName,
			[string] $fileType,
			[string] $silentArgs,
			[string] $file
		)

		$script:uninstallCall = $PSBoundParameters
	}

	. (Join-Path $repoRoot 'tools/chocolateyuninstall.ps1')

	Assert-Equal $script:uninstallCall.packageName 'duo-auth-proxy' 'Uninstall packageName mismatch.'
	Assert-Equal $script:uninstallCall.fileType 'exe' 'Uninstall fileType mismatch.'
	Assert-Equal $script:uninstallCall.silentArgs '/S' 'Uninstall silent args mismatch.'
	Assert-Equal $script:uninstallCall.file 'C:\Program Files\Duo Security Authentication Proxy\uninstall.exe' 'Uninstall file mismatch.'
}

if ($failures.Count -gt 0) {
	Write-Host ''
	Write-Host "$($failures.Count) test(s) failed:"
	foreach ($failure in $failures) {
		Write-Host " - $failure"
	}
	exit 1
}

Write-Host ''
Write-Host 'All tests passed.'
