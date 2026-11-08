$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()
$results = [System.Collections.Generic.List[pscustomobject]]::new()

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
		$results.Add([pscustomobject] @{ Name = $Name; Passed = $true; Message = '' })
	}
	catch {
		$failures.Add("$Name - $($_.Exception.Message)")
		Write-Host "[FAIL] $Name"
		Write-Host "       $($_.Exception.Message)"
		$results.Add([pscustomobject] @{ Name = $Name; Passed = $false; Message = $_.Exception.Message })
	}
}

function Write-TestSummary {
	if (-not $env:GITHUB_STEP_SUMMARY) {
		return
	}

	$lines = [System.Collections.Generic.List[string]]::new()
	$lines.Add('## Test results')
	$lines.Add('')
	$lines.Add("$($results.Count - $failures.Count) of $($results.Count) tests passed.")
	$lines.Add('')
	$lines.Add('| Status | Test | Details |')
	$lines.Add('| --- | --- | --- |')

	foreach ($result in $results) {
		$status = if ($result.Passed) { '✅' } else { '❌' }
		$details = if ($result.Passed) { '' } else { ($result.Message -replace '\|', '\|') -replace "`r?`n", '<br/>' }
		$lines.Add("| $status | $($result.Name) | $details |")
	}

	Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value ($lines -join [System.Environment]::NewLine)
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

Invoke-Test 'Duo update checker parses the current Windows release and checksum' {
	. (Join-Path $repoRoot 'scripts/Check-DuoAuthProxyUpdate.ps1') -WebhookUrl 'https://example.test/webhook'

	$release = Get-LatestDuoAuthProxyRelease -ChecksumsContent @'
## Duo Authentication Proxy
### Windows
#### Current Release
<a href="https://dl.duosecurity.com/duoauthproxy-6.8.1.exe">bbb051a35be93ea3ce600d406c3cdd28f520a7aef224186c96479a4572d59b6e  duoauthproxy-6.8.1.exe
'@

	Assert-Equal $release.Version.ToString() '6.8.1' 'Update checker version mismatch.'
	Assert-Equal $release.Checksum 'bbb051a35be93ea3ce600d406c3cdd28f520a7aef224186c96479a4572d59b6e' 'Update checker checksum mismatch.'
	Assert-Equal $release.Url 'https://dl.duosecurity.com/duoauthproxy-6.8.1.exe' 'Update checker installer URL mismatch.'
}

Invoke-Test 'Duo update checker rejects a missing current Windows release' {
	. (Join-Path $repoRoot 'scripts/Check-DuoAuthProxyUpdate.ps1') -WebhookUrl 'https://example.test/webhook'

	try {
		Get-LatestDuoAuthProxyRelease -ChecksumsContent '## Duo Authentication Proxy'
		throw 'The update checker unexpectedly accepted missing release data.'
	}
	catch {
		Assert-Match $_.Exception.Message 'current Duo Authentication Proxy Windows release was not found' 'Unexpected missing release error.'
	}
}

foreach ($currentVersion in @('6.8.0', '6.8.1')) {
	Invoke-Test "Duo update checker emits workflow outputs for $currentVersion" {
		. (Join-Path $repoRoot 'scripts/Check-DuoAuthProxyUpdate.ps1')
		function Get-PackageVersion { return [version] $currentVersion }
		function Invoke-WebRequest {
			return [pscustomobject] @{
				Content = '<a href="https://dl.duosecurity.com/duoauthproxy-6.8.1.exe">bbb051a35be93ea3ce600d406c3cdd28f520a7aef224186c96479a4572d59b6e  duoauthproxy-6.8.1.exe'
			}
		}

		$outputFile = New-TemporaryFile
		$previousOutput = $env:GITHUB_OUTPUT
		try {
			$env:GITHUB_OUTPUT = $outputFile.FullName
			Invoke-DuoAuthProxyUpdateCheck
			$output = Get-Content -Raw -Path $outputFile.FullName
			$expectedUpdate = ($currentVersion -eq '6.8.0').ToString().ToLowerInvariant()
			Assert-Match $output "update_available=$expectedUpdate" 'Update availability output mismatch.'
			Assert-Match $output 'version=6\.8\.1' 'Release version output mismatch.'
		}
		finally {
			$env:GITHUB_OUTPUT = $previousOutput
			Remove-Item -LiteralPath $outputFile.FullName
		}
	}
}

foreach ($case in @(
	@{ Name = 'pushes a new version'; Status = 404; ExitCode = 0; Key = 'test-key'; Pushes = 1; Error = $null },
	@{ Name = 'skips an existing version'; Status = 200; ExitCode = 0; Key = 'test-key'; Pushes = 0; Error = $null },
	@{ Name = 'rejects a missing API key'; Status = 404; ExitCode = 0; Key = ''; Pushes = 0; Error = 'secret is not configured' },
	@{ Name = 'rejects a failed feed lookup'; Status = 503; ExitCode = 0; Key = 'test-key'; Pushes = 0; Error = 'HTTP 503' },
	@{ Name = 'rejects an unauthorized feed lookup'; Status = 401; ExitCode = 0; Key = 'test-key'; Pushes = 0; Error = 'HTTP 401' },
	@{ Name = 'reports a failed push'; Status = 404; ExitCode = 1; Key = 'test-key'; Pushes = 1; Error = 'exit code 1' }
)) {
	Invoke-Test "Chocolatey publisher $($case.Name)" {
		. (Join-Path $repoRoot 'scripts/Publish-ChocolateyPackage.ps1') -Version '6.8.1'
		$script:pushCalls = 0
		function Invoke-WebRequest {
			param($Uri, $Method, [switch] $SkipHttpErrorCheck)
			Assert-Equal $Uri 'https://community.chocolatey.org/api/v2/package/duo-auth-proxy/6.8.1' 'Unexpected package lookup URL.'
			Assert-Equal $Method 'Head' 'Unexpected package lookup method.'
			return [pscustomobject] @{ StatusCode = $case.Status }
		}
		function choco {
			$script:pushCalls++
			Assert-Equal $args[0] 'push' 'Expected a package push.'
			Assert-Equal $args[1] (Join-Path $repoRoot 'duo-auth-proxy.nuspec') 'Unexpected package path.'
			Assert-Equal $args[3] 'https://push.chocolatey.org/' 'Unexpected push destination.'
			Assert-Equal $args[5] 'test-key' 'Unexpected API key.'
			$script:LASTEXITCODE = $case.ExitCode
		}

		$previousKey = $env:CHOCOLATEY_API_KEY
		$previousExitCode = $LASTEXITCODE
		try {
			$env:CHOCOLATEY_API_KEY = $case.Key
			$errorMessage = $null
			try {
				Publish-ChocolateyPackage -Version '6.8.1' -PackagePath (Join-Path $repoRoot 'duo-auth-proxy.nuspec')
			}
			catch {
				$errorMessage = $_.Exception.Message
			}
			if ($case.Error) {
				Assert-Match $errorMessage $case.Error 'Unexpected publication error.'
			}
			else {
				Assert-Equal $errorMessage $null 'Unexpected publication failure.'
			}
			Assert-Equal $script:pushCalls $case.Pushes 'Unexpected number of package pushes.'
		}
		finally {
			$env:CHOCOLATEY_API_KEY = $previousKey
			$script:LASTEXITCODE = $previousExitCode
		}
	}
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

Write-TestSummary

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
