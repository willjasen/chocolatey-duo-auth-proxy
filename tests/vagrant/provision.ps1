$ErrorActionPreference = 'Stop'

$repoRoot = 'C:\vagrant'
$nuspecPath = Join-Path $repoRoot 'duo-auth-proxy.nuspec'
$packageOutput = Join-Path $repoRoot 'packages\vagrant'
$installLogPath = 'C:\ProgramData\chocolatey\logs\chocolatey.log'

function Invoke-NativeCommand {
	param(
		[Parameter(Mandatory = $true)]
		[string] $FilePath,

		[Parameter()]
		[string[]] $ArgumentList = @()
	)

	& $FilePath @ArgumentList

	if ($LASTEXITCODE -ne 0) {
		throw "$FilePath $($ArgumentList -join ' ') failed with exit code $LASTEXITCODE."
	}
}

function Get-PackageVersion {
	[xml] $nuspec = Get-Content -Raw -Path $nuspecPath
	$namespace = New-Object System.Xml.XmlNamespaceManager($nuspec.NameTable)
	$namespace.AddNamespace('nuspec', 'http://schemas.microsoft.com/packaging/2015/06/nuspec.xsd')

	return $nuspec.SelectSingleNode('/nuspec:package/nuspec:metadata/nuspec:version', $namespace).InnerText
}

function Get-ChocolateyPath {
	$command = Get-Command choco.exe -ErrorAction SilentlyContinue
	if ($command) {
		return $command.Source
	}

	$defaultPath = Join-Path $env:ProgramData 'chocolatey\bin\choco.exe'
	if (Test-Path $defaultPath) {
		return $defaultPath
	}

	return $null
}

function Install-ChocolateyIfNeeded {
	if (Get-ChocolateyPath) {
		Write-Host 'Chocolatey is already installed.'
		return
	}

	Write-Host 'Installing Chocolatey.'
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	Set-ExecutionPolicy Bypass -Scope Process -Force
	Invoke-Expression ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

	$chocolateyPath = Get-ChocolateyPath
	if (-not $chocolateyPath) {
		throw 'Chocolatey installation completed, but choco.exe was not found on PATH.'
	}

	$env:Path = "$(Split-Path -Parent $chocolateyPath);$env:Path"
}

function Assert-DuoAuthProxyInstalled {
	$uninstallKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DuoAuthProxy'
	$uninstallItem = Get-ItemProperty -Path $uninstallKey -ErrorAction Stop

	if (-not $uninstallItem.UninstallString) {
		throw 'Duo Authentication Proxy uninstall string was not found in the registry.'
	}

	$service = Get-Service -Name 'DuoAuthProxy' -ErrorAction SilentlyContinue
	if (-not $service) {
		$service = Get-Service | Where-Object { $_.DisplayName -like '*Duo*Authentication*Proxy*' } | Select-Object -First 1
	}

	if (-not $service) {
		throw 'Duo Authentication Proxy Windows service was not found after installation.'
	}

	Write-Host "$($service.Name) service exists with status: $($service.Status)."
}

$version = Get-PackageVersion
Install-ChocolateyIfNeeded
$chocolateyPath = Get-ChocolateyPath

Invoke-NativeCommand -FilePath $chocolateyPath -ArgumentList @('feature', 'enable', '--name=allowGlobalConfirmation')

if (Test-Path $packageOutput) {
	Remove-Item -Path $packageOutput -Recurse -Force
}

New-Item -Path $packageOutput -ItemType Directory -Force | Out-Null

Write-Host "Building duo-auth-proxy $version package inside the VM."
Invoke-NativeCommand -FilePath $chocolateyPath -ArgumentList @('pack', $nuspecPath, "--outputdirectory=$packageOutput")

Write-Host "Installing duo-auth-proxy $version from the locally built package."
Invoke-NativeCommand -FilePath $chocolateyPath -ArgumentList @(
	'install',
	'duo-auth-proxy',
	"--version=$version",
	"--source=$packageOutput",
	'--yes',
	'--no-progress',
	'--force'
)

Assert-DuoAuthProxyInstalled

$pushApiKey = $env:DUO_PUSH_API_KEY
$pushSource = $env:DUO_PUSH_SOURCE
$shouldPush = $false

if (-not [string]::IsNullOrWhiteSpace($pushApiKey)) {
	$promptValue = $env:DUO_PUSH_CONFIRM
	if (-not [string]::IsNullOrWhiteSpace($promptValue)) {
		$shouldPush = $promptValue -match '^(1|true|yes|y)$'
	}
	else {
		try {
			$response = Read-Host 'A Chocolatey push API key was found. Push the package to the Chocolatey feed? [y/N]'
			$shouldPush = $response -match '^(y|yes)$'
		}
		catch {
			Write-Host 'No interactive response was provided. Skipping package push.'
			$shouldPush = $false
		}
	}
}
else {
	try {
		$manualApiKey = Read-Host 'No Chocolatey push API key was provided. Enter the API key to push the package, or press Enter to skip.'
		if (-not [string]::IsNullOrWhiteSpace($manualApiKey)) {
			$pushApiKey = $manualApiKey
			$shouldPush = $true
		}
	}
	catch {
		Write-Host 'No interactive response was provided. Skipping package push.'
		$shouldPush = $false
	}
}

if ($shouldPush) {
	if ([string]::IsNullOrWhiteSpace($pushSource)) {
		$pushSource = 'https://push.chocolatey.org/'
	}

	$packagePath = Join-Path $packageOutput "duo-auth-proxy.$version.nupkg"
	if (-not (Test-Path $packagePath)) {
		throw "Expected package was not created at $packagePath."
	}

	$communityFeedUrl = 'https://community.chocolatey.org/api/v2/package/duo-auth-proxy/'
	$versionExists = $false
	try {
		$packageResponse = Invoke-WebRequest -Uri "$communityFeedUrl$version" -Method Head -UseBasicParsing -ErrorAction SilentlyContinue
		$versionExists = $packageResponse.StatusCode -eq 200
	}
	catch {
		$versionExists = $false
	}

	if ($versionExists) {
		Write-Host "Package version $version already exists on the Chocolatey Community feed. Skipping push."
	}
	else {
		Write-Host "Configuring Chocolatey API key for $pushSource."
		Invoke-NativeCommand -FilePath $chocolateyPath -ArgumentList @('apikey', '--key', $pushApiKey, '--source', $pushSource)

		Write-Host "Pushing $packagePath to $pushSource."
		Invoke-NativeCommand -FilePath $chocolateyPath -ArgumentList @('push', $packagePath, '--source', $pushSource)
	}
}
else {
	Write-Host 'Package push skipped. Set DUO_PUSH_CONFIRM=true to publish the package.'
}

if ($env:DUO_TEST_UNINSTALL -eq 'true') {
	Write-Host "Uninstalling duo-auth-proxy $version."
	Invoke-NativeCommand -FilePath $chocolateyPath -ArgumentList @(
		'uninstall',
		'duo-auth-proxy',
		"--version=$version",
		'--yes',
		'--no-progress'
	)
}

if (Test-Path $installLogPath) {
	Write-Host "Chocolatey log: $installLogPath"
}

Write-Host 'Duo Authentication Proxy Vagrant integration test completed successfully.'
