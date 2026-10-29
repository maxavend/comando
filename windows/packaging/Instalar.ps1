# Installs Comando from this folder: trusts its test certificate and adds the
# package with its dependencies. Windows asks for administrator permission
# once, to trust the certificate.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$certificate = Join-Path $here 'Comando.cer'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$($MyInvocation.MyCommand.Path)`"" -Wait
    return
}

Import-Certificate -FilePath $certificate -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null

$package = Get-ChildItem -Path $here -Recurse -Filter '*.msix' | Where-Object { $_.DirectoryName -notlike '*Dependencies*' } | Select-Object -First 1
$architecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
$dependencies = Get-ChildItem -Path $here -Recurse -Filter '*.msix' | Where-Object { $_.DirectoryName -like "*Dependencies*$architecture*" } | ForEach-Object FullName

Add-AppxPackage -Path $package.FullName -DependencyPath $dependencies -ForceApplicationShutdown
Write-Host 'Comando quedó instalado. Ábrelo desde el menú Inicio.'
