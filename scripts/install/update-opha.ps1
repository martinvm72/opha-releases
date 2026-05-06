<#
Opha — mise à jour manuelle (Windows) — packaging V1 / P.3.

Usage : .\update-opha.ps1
#>

$ErrorActionPreference = 'Stop'
$OphaHome = if ($env:OPHA_HOME) { $env:OPHA_HOME } else { Join-Path $env:USERPROFILE 'Opha' }

if (-not (Test-Path (Join-Path $OphaHome '.env'))) {
    Write-Host "✗ Aucune installation Opha détectée à $OphaHome." -ForegroundColor Red
    Write-Host "  Lancez d'abord install-opha.ps1." -ForegroundColor Red
    exit 1
}

Push-Location $OphaHome
try {
    Write-Host "`n== Mise à jour d'Opha ==" -ForegroundColor Cyan
    Write-Host "▶ Pull des images..." -ForegroundColor Green
    & docker compose -f docker-compose.prod.yml --env-file .env pull

    Write-Host "▶ Redémarrage de la stack..." -ForegroundColor Green
    & docker compose -f docker-compose.prod.yml --env-file .env up -d
} finally {
    Pop-Location
}

Write-Host "`nMise à jour terminée. Vérifiez https://opha.local`n"
