[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[ValidatePattern('^\d+\.\d+\.\d+$')]
	[string] $Version
)

$ErrorActionPreference = 'Stop'

function Publish-ChocolateyPackage {
	param(
		[Parameter(Mandatory = $true)]
		[string] $Version,

		[Parameter(Mandatory = $true)]
		[string] $PackagePath
	)

	if ([string]::IsNullOrWhiteSpace($env:CHOCOLATEY_API_KEY)) {
		throw 'The CHOCOLATEY_API_KEY repository secret is not configured.'
	}
	if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
		throw "Package was not found at $PackagePath."
	}

	$response = Invoke-WebRequest -Uri "https://community.chocolatey.org/api/v2/package/duo-auth-proxy/$Version" -Method Head -SkipHttpErrorCheck
	if ($response.StatusCode -eq 200) {
		Write-Host "duo-auth-proxy $Version has already been submitted; skipping duplicate push."
		return
	}
	if ($response.StatusCode -ne 404) {
		throw "Chocolatey package lookup failed with HTTP $($response.StatusCode)."
	}

	choco push $PackagePath --source https://push.chocolatey.org/ --api-key $env:CHOCOLATEY_API_KEY --yes
	if ($LASTEXITCODE -ne 0) {
		throw "Chocolatey push failed with exit code $LASTEXITCODE."
	}
}

if ($MyInvocation.InvocationName -ne '.') {
	$repoRoot = Split-Path -Parent $PSScriptRoot
	Publish-ChocolateyPackage -Version $Version -PackagePath (Join-Path $repoRoot "packages/duo-auth-proxy.$Version.nupkg")
}
