$ErrorActionPreference = 'Stop'
$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  softwareName  = 'DuoAuthProxy'
  fileType      = 'exe'
  silentArgs    = '/S'
  file			= (Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DuoAuthProxy").UninstallString
}

Uninstall-ChocolateyPackage $packageArgs['packageName'] $packageArgs['fileType'] $packageArgs['silentArgs'] $packageArgs['file']