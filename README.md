# Chocolatey: Duo Authentication Proxy

[![Chocolatey package version](https://img.shields.io/chocolatey/v/duo-auth-proxy)](https://chocolatey.org/packages/duo-auth-proxy)
[![Chocolatey package download count](https://img.shields.io/chocolatey/dt/duo-auth-proxy)](https://chocolatey.org/packages/duo-auth-proxy)

 - This is a [Chocolatey](https://chocolatey.org/) package to install the [Duo Authentication Proxy](https://duo.com)
 - This Chocolatey package can be found at [here](https://community.chocolatey.org/packages/duo-auth-proxy/)

The Duo Authentication Proxy (from Cisco) is an on-premises software service that receives authentication requests from your local devices and applications via RADIUS or LDAP, optionally performs primary authentication against your existing LDAP directory or RADIUS authentication server, and then contacts Duo to perform secondary authentication.

This software is generally installed on platforms like Windows Server. If you are looking for the Duo application package deployed to Windows endpoints, you can find it [here](https://community.chocolatey.org/packages/duo-authentication).

## Installation
1. Install [Chocolatey](https://chocolatey.org/) if needed
2. Run in Powershell - `choco install duo-auth-proxy`

## Testing
Run the package checks with PowerShell:

```powershell
./tests/run-tests.ps1
```

The tests validate the nuspec metadata, confirm the installer URL/checksum and packaged `.nupkg` match the current version, and mock the Chocolatey install/uninstall helpers so the package scripts can be checked without installing Duo or starting a VM.

## Duo release notifications

The `Check Duo Authentication Proxy update` GitHub Actions workflow runs daily and can also be started manually. It reads Duo's published Windows checksum page and compares the newest release to the nuspec version. When a newer release is available, it sends a JSON `POST` notification containing the current and latest versions, installer URL, and SHA-256 checksum.

To enable notifications, add a repository Actions secret named `DUO_UPDATE_WEBHOOK_URL`. If the secret is absent, the workflow continues without making an outbound webhook request.

When a newer release is found, the workflow automatically updates the nuspec and install script, packs and validates the package, and pushes it to the Chocolatey Community Repository without waiting for a pull request merge. Add your Chocolatey maintainer API key as a repository Actions secret named `CHOCOLATEY_API_KEY`. Publishing fails clearly if that secret is missing. Chocolatey moderation still applies; a successful push is a submission, not immediate public approval.

After a successful submission, the workflow commits the updated metadata to `main` using `GITHUB_TOKEN`. Repository rules must permit this Actions bot push. If recording the version fails, the workflow reports an error; a retry skips a package already present on the Chocolatey feed and tries recording the version again. Publishing workflows share a concurrency group to prevent simultaneous submissions.

The `Publish Chocolatey package` workflow remains available for manual publishing and package changes pushed to `main`. It also validates the package before submission and skips versions already on the feed. No update pull request is created by the scheduled checker anymore.

### Vagrant integration test
To test the real Chocolatey install inside a Windows VM, install Vagrant and VirtualBox, then run:

```powershell
./tests/run-vagrant-install-test.ps1
```

This builds the package from the current working tree inside the VM, installs it with Chocolatey from that local package source, and verifies the Duo Authentication Proxy registry entry and Windows service exist.

The default box is `gusztavvargadr/windows-server-2022-standard`. To use a different Windows box:

```powershell
$env:VAGRANT_WINDOWS_BOX = 'your/windows-box'
./tests/run-vagrant-install-test.ps1
```

The VM is left running for inspection. Clean it up with:

```powershell
vagrant destroy -f
```

## References
 - [Duo Authentication Proxy - Reference](https://duo.com/docs/authproxy-reference)
 - [Duo Downloads and Checksums for Windows](https://duo.com/docs/checksums#windows)
