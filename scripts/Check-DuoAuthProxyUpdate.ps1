[CmdletBinding()]
param(
	[Parameter()]
	[string] $WebhookUrl
)

$ErrorActionPreference = 'Stop'

$checksumsUrl = 'https://duo.com/docs/checksums'
$repoRoot = Split-Path -Parent $PSScriptRoot
$nuspecPath = Join-Path $repoRoot 'duo-auth-proxy.nuspec'

function Get-PackageVersion {
	param(
		[Parameter(Mandatory = $true)]
		[string] $Path
	)

	[xml] $nuspec = Get-Content -Raw -Path $Path
	$namespace = New-Object System.Xml.XmlNamespaceManager($nuspec.NameTable)
	$namespace.AddNamespace('nuspec', 'http://schemas.microsoft.com/packaging/2015/06/nuspec.xsd')
	$versionNode = $nuspec.SelectSingleNode('/nuspec:package/nuspec:metadata/nuspec:version', $namespace)

	if (-not $versionNode) {
		throw "Package version was not found in $Path."
	}

	return [version] $versionNode.InnerText
}

function Get-LatestDuoAuthProxyRelease {
	param(
		[Parameter(Mandatory = $true)]
		[string] $ChecksumsContent
	)

	$matches = [regex]::Matches(
		$ChecksumsContent,
		'(?i)<a href="https://dl\.duosecurity\.com/duoauthproxy-(?<version>\d+\.\d+\.\d+)\.exe">(?<checksum>[a-f0-9]{64})\s+duoauthproxy-\k<version>\.exe'
	)

	if ($matches.Count -eq 0) {
		throw 'The current Duo Authentication Proxy Windows release was not found on the Duo checksums page.'
	}

	$match = $matches |
		Sort-Object { [version] $_.Groups['version'].Value } -Descending |
		Select-Object -First 1

	return [pscustomobject] @{
		Version  = [version] $match.Groups['version'].Value
		Checksum = $match.Groups['checksum'].Value.ToLowerInvariant()
		Url      = "https://dl.duosecurity.com/duoauthproxy-$($match.Groups['version'].Value).exe"
	}
}

function Invoke-DuoAuthProxyUpdateCheck {
	param(
		[Parameter()]
		[string] $WebhookUrl
	)

	$currentVersion = Get-PackageVersion -Path $nuspecPath
	$checksumsResponse = Invoke-WebRequest -Uri $checksumsUrl -UseBasicParsing
	$latestRelease = Get-LatestDuoAuthProxyRelease -ChecksumsContent $checksumsResponse.Content
	$updateAvailable = $latestRelease.Version -gt $currentVersion

	if ($updateAvailable) {
		Write-Host "Duo Authentication Proxy $($latestRelease.Version) is available; package version is $currentVersion."
	}
	else {
		Write-Host "Duo Authentication Proxy is current at version $currentVersion."
	}

	$workflowRunUrl = if ($env:GITHUB_SERVER_URL -and $env:GITHUB_REPOSITORY -and $env:GITHUB_RUN_ID) {
		"$env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID"
	}
	else {
		$null
	}

	$content = if ($updateAvailable) {
		"Duo Authentication Proxy $($latestRelease.Version) is available (package is at $currentVersion)."
	}
	else {
		"Duo Authentication Proxy is current at version $currentVersion."
	}

	# Discord webhooks reject a payload without a non-empty "content" or "embeds" field
	# (error code 50006, "Cannot send an empty message"), so the message text is required here.
	$payload = @{
		content          = $content
		event            = if ($updateAvailable) { 'duo_auth_proxy_update_available' } else { 'duo_auth_proxy_up_to_date' }
		update_available = $updateAvailable
		current_version  = $currentVersion.ToString()
		latest_version   = $latestRelease.Version.ToString()
		installer_url    = $latestRelease.Url
		sha256           = $latestRelease.Checksum
		checksums_url    = $checksumsUrl
		repository       = $env:GITHUB_REPOSITORY
		workflow_run_url = $workflowRunUrl
	}

	if ([string]::IsNullOrWhiteSpace($WebhookUrl)) {
		Write-Warning 'DUO_UPDATE_WEBHOOK_URL is not configured; no webhook was sent.'
		return
	}

	Invoke-RestMethod -Uri $WebhookUrl -Method Post -ContentType 'application/json' -Body ($payload | ConvertTo-Json -Depth 3)
	Write-Host 'Update webhook sent.'
}

if ($MyInvocation.InvocationName -ne '.') {
	Invoke-DuoAuthProxyUpdateCheck -WebhookUrl $WebhookUrl
}
