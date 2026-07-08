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
