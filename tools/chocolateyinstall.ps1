$ErrorActionPreference = 'Stop'
$toolsDir   = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$version	= '6.8.1'
$url		= "https://dl.duosecurity.com/duoauthproxy-6.8.1.exe"

$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  unzipLocation = $toolsDir
  fileType      = 'exe'
  url           = $url

  softwareName  = 'Duo Security Authentication Proxy*'

  checksum      = 'a108494fd20c1a6ae4fb0ecb346688639f6d8c261cc6bab7709c1af76be0b47b'
  checksumType  = 'sha256'

  silentArgs    = "/S"
  validExitCodes= @(0, 3010, 1641)
}

$OSVersion = [System.Environment]::OSVersion.Version
$RequiredMajorVersion = 10
$RequiredMinorVersion = 0
$RequiredBuildVersion = 14393

function Test-DuoAuthProxySupportedOS {
	param(
		[Parameter(Mandatory = $true)]
		[version] $Version
	)

	return -not (
		$Version.Major -lt $RequiredMajorVersion -or
		($Version.Major -eq $RequiredMajorVersion -and $Version.Minor -lt $RequiredMinorVersion) -or
		($Version.Major -eq $RequiredMajorVersion -and $Version.Minor -eq $RequiredMinorVersion -and $Version.Build -lt $RequiredBuildVersion)
	)
}

if ( -not (Test-DuoAuthProxySupportedOS -Version $OSVersion) )
	{
	Write-Error "This package requires Windows version $RequiredMajorVersion.$RequiredMinorVersion.$RequiredBuildVersion or higher."
	throw "Unsupported operating system version."
}
else {
	Install-ChocolateyPackage @packageArgs
}
