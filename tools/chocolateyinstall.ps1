$ErrorActionPreference = 'Stop'
$toolsDir   = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$url        = 'https://dl.duosecurity.com/duoauthproxy-6.4.1.exe'

$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  unzipLocation = $toolsDir
  fileType      = 'exe'
  url           = $url

  softwareName  = 'Duo Security Authentication Proxy*'

  checksum      = '0ec2f58c035a703e50cf30ac22d7beae27b2dd3182d5565552e00988e4570eaa'
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
