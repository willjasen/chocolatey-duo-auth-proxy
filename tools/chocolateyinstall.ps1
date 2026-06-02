$ErrorActionPreference = 'Stop'
$toolsDir   = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$url        = 'https://dl.duosecurity.com/duoauthproxy-6.7.0.exe'

$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  unzipLocation = $toolsDir
  fileType      = 'exe'
  url           = $url

  softwareName  = 'Duo Security Authentication Proxy*'

  checksum      = '098b21d31f989b2da01eb0ad447cd49eab56b7e0f72a7a38cc94fec6cdab2e76'
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
