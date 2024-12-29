$ErrorActionPreference = 'Stop'
$toolsDir   = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$url        = 'https://dl.duosecurity.com/duoauthproxy-6.4.2.exe'

$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  unzipLocation = $toolsDir
  fileType      = 'exe'
  url           = $url

  softwareName  = 'Duo Security Authentication Proxy*'

  checksum      = '5bf1d93a21616fb323825cc242c82aa2abe44fce6572e823041eb8f04c0463ae'
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
