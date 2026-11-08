[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[ValidatePattern('^\d+\.\d+\.\d+$')]
	[string] $Version
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$packagePath = Join-Path $repoRoot "packages/duo-auth-proxy.$Version.nupkg"
$tag = "v$Version"

if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
	throw "Package was not found at $packagePath."
}
if ([string]::IsNullOrWhiteSpace($env:GITHUB_REPOSITORY)) {
	throw 'GITHUB_REPOSITORY is not configured.'
}

$tags = gh api "repos/$env:GITHUB_REPOSITORY/releases" --paginate --jq '.[].tag_name'
if ($LASTEXITCODE -ne 0) {
	throw 'Failed to check existing GitHub releases.'
}

if ($tags -contains $tag) {
	gh release upload $tag $packagePath --repo $env:GITHUB_REPOSITORY --clobber
	if ($LASTEXITCODE -ne 0) {
		throw "Failed to upload the package to GitHub release $tag."
	}
}
else {
	$commit = git rev-parse HEAD
	if ($LASTEXITCODE -ne 0) {
		throw 'Failed to read the package commit for the GitHub release.'
	}
	gh release create $tag $packagePath --repo $env:GITHUB_REPOSITORY --target $commit --title $tag --notes "Duo Authentication Proxy $Version Chocolatey package. Submitted to the Chocolatey Community Repository; moderation still applies."
	if ($LASTEXITCODE -ne 0) {
		throw "Failed to create GitHub release $tag."
	}
}
