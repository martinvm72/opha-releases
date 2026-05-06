<#
Opha — désinstalleur Windows — packaging V1 / P.3.

Logique identique à la version macOS (cf. uninstall-opha.command).
#>

$ErrorActionPreference = 'Stop'
$OphaHome = if ($env:OPHA_HOME) { $env:OPHA_HOME } else { Join-Path $env:USERPROFILE 'Opha' }

if (-not (Test-Path (Join-Path $OphaHome 'docker-compose.prod.yml'))) {
    Write-Host "✗ Aucune installation Opha détectée à $OphaHome." -ForegroundColor Red
    exit 1
}

Write-Host "`n== Désinstallation d'Opha ==`n" -ForegroundColor Cyan

Push-Location $OphaHome
try {
    Write-Host "▶ Arrêt de la stack..." -ForegroundColor Green
    & docker compose -f docker-compose.prod.yml --env-file .env down
} finally {
    Pop-Location
}

Write-Host @"

Voulez-vous SUPPRIMER les données Opha ?
  - Base Postgres (patients, consultations, prescriptions, etc.)
  - Documents patient (PDF, OCT, courriers)
  - Keystore eHealth
  - Certificats Caddy
Cette opération est irréversible.
"@ -ForegroundColor Yellow

$confirm = Read-Host "Tapez 'OUI EFFACER' pour confirmer (autre chose = annuler)"

if ($confirm -eq 'OUI EFFACER') {
    Push-Location $OphaHome
    try {
        Write-Host "▶ Suppression des volumes..." -ForegroundColor Red
        & docker compose -f docker-compose.prod.yml --env-file .env down -v
    } finally {
        Pop-Location
    }
    Write-Host "▶ Volumes Opha supprimés." -ForegroundColor Green
} else {
    Write-Host "▶ Volumes préservés (docker volume ls pour les voir)." -ForegroundColor Green
}

$rmdir = Read-Host "Supprimer aussi le dossier $OphaHome ? [o/N]"
if ($rmdir -match '^[oOyY]$') {
    Remove-Item -Recurse -Force $OphaHome
    Write-Host "▶ Dossier supprimé." -ForegroundColor Green
}

$rmhosts = Read-Host "Retirer l'entrée 127.0.0.1 opha.local de hosts ? [o/N]"
if ($rmhosts -match '^[oOyY]$') {
    $hosts = "$env:WINDIR\System32\drivers\etc\hosts"
    $content = Get-Content $hosts | Where-Object {
        $_ -notmatch '^\s*127\.0\.0\.1\s+opha\.local(\s|$)'
    }
    Set-Content -Path $hosts -Value $content
    Write-Host "▶ hosts nettoyé." -ForegroundColor Green
}

Write-Host "`nDésinstallation terminée.`n"
