$ErrorActionPreference = 'Stop'
$toolsDir   = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$url        = 'https://dl.duosecurity.com/duoauthproxy-6.5.1.exe'

$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  unzipLocation = $toolsDir
  fileType      = 'exe'
  url           = $url

  softwareName  = 'Duo Security Authentication Proxy*'

  checksum      = '44cb53c6d5430e85619a9dbcea10df0daaa6242f0e5197879401e6bbbfb6734f'
  checksumType  = 'sha256'

  silentArgs    = "/S"
  validExitCodes= @(0, 3010, 1641)
}

$OSVersion = [System.Environment]::OSVersion.Version
$RequiredMajorVersion = 10
$RequiredMinorVersion = 0
$RequiredBuildVersion = 14393

if ( $OSVersion.Major -lt $RequiredMajorVersion -or
	($OSVersion.Major -eq $RequiredMajorVersion -and $OSVersion.Minor -lt $RequiredMinorVersion) -or
	($OSVersion.Major -eq $RequiredMajorVersion -and $OSVersion.Minor -eq $RequiredMinorVersion -and $OSVersion.Build -lt $RequiredBuildVersion) )
	{
		Write-Error "This package requires Windows version $RequiredMajorVersion.$RequiredMinorVersion.$RequiredBuildVersion or higher."
		throw "Unsupported operating system version."
}
else {
	Install-ChocolateyPackage @packageArgs
}
