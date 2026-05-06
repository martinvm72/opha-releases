<#
Opha — configuration d'un PC client (Windows) — packaging V1 / P.3.

Sur Windows ≥ 10 1803, mDNS résout opha.local nativement. Ce script est
un fallback : il ajoute l'IP du serveur dans hosts.

Usage (terminal admin) : .\setup-client.ps1 [-ServerIP 192.168.1.42]
#>

[CmdletBinding()]
param(
    [string]$ServerIP   = '',
    [string]$OphaHostname = $(if ($env:OPHA_HOSTNAME) { $env:OPHA_HOSTNAME } else { 'opha.local' })
)

$ErrorActionPreference = 'Stop'

function Ensure-Admin {
    $current = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Élévation UAC nécessaire pour modifier hosts. Relance..." -ForegroundColor Yellow
        $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        if ($ServerIP) { $args += " -ServerIP $ServerIP" }
        Start-Process -FilePath PowerShell -Verb RunAs -ArgumentList $args
        exit 0
    }
}

Ensure-Admin

if (-not $ServerIP) {
    Write-Host "`nConfiguration du PC client pour atteindre Opha`n" -ForegroundColor Cyan
    $ServerIP = Read-Host "IP du serveur Opha"
}

if ($ServerIP -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
    Write-Host "✗ IP invalide : '$ServerIP'." -ForegroundColor Red
    exit 1
}

$hostsFile = "$env:WINDIR\System32\drivers\etc\hosts"
$pattern   = "^\s*\d{1,3}(\.\d{1,3}){3}\s+$([regex]::Escape($OphaHostname))(\s|$)"

# Supprime toute entrée existante pour ce hostname.
$content = Get-Content $hostsFile | Where-Object { $_ -notmatch $pattern }
$content += "$ServerIP $OphaHostname"
Set-Content -Path $hostsFile -Value $content

Write-Host "`n▶ Entrée '$ServerIP $OphaHostname' ajoutée à $hostsFile." -ForegroundColor Green
Write-Host "`nConfiguration terminée. Ouvrez https://$OphaHostname dans votre navigateur."
Write-Host "Au 1er accès, acceptez l'avertissement de sécurité (cert auto-signé).`n"
