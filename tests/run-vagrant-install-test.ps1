$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not (Get-Command vagrant -ErrorAction SilentlyContinue)) {
	throw 'Vagrant was not found. Install Vagrant and VirtualBox, then run this test again.'
}

Push-Location $repoRoot
try {
	Write-Host 'Starting the Windows Vagrant integration test. This may take a while the first time.'
	& vagrant up --provision

	if ($LASTEXITCODE -ne 0) {
		throw "Vagrant integration test failed with exit code $LASTEXITCODE."
	}

	Write-Host ''
	Write-Host 'Vagrant integration test passed.'
	Write-Host 'Run `vagrant destroy -f` when you are done with the VM.'
}
finally {
	Pop-Location
}
