<#
=============================================================================
Opha — installeur Windows (packaging V1 / P.3)
=============================================================================

PowerShell 5.1+ (préinstallé sur Windows 10/11). Logique : cf.
install-opha.command.

Usage (clic droit > Exécuter avec PowerShell, OU dans un terminal admin) :
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    .\install-opha.ps1

Le script demande l'élévation UAC pour modifier hosts et hostname.
=============================================================================
#>

[CmdletBinding()]
param(
    [string]$OphaRepo     = $(if ($env:OPHA_REPO)     { $env:OPHA_REPO }     else { 'martinvm72/opha-releases' }),
    [string]$OphaBranch   = $(if ($env:OPHA_BRANCH)   { $env:OPHA_BRANCH }   else { 'main' }),
    [string]$OphaHome     = $(if ($env:OPHA_HOME)     { $env:OPHA_HOME }     else { Join-Path $env:USERPROFILE 'Opha' }),
    [string]$OphaHostname = $(if ($env:OPHA_HOSTNAME) { $env:OPHA_HOSTNAME } else { 'opha.local' }),
    # Override pour forcer une version spécifique au lieu de lire latest.txt.
    [string]$OphaVersion  = $(if ($env:OPHA_VERSION)  { $env:OPHA_VERSION }  else { '' })
)

$ErrorActionPreference = 'Stop'

function Step($msg)  { Write-Host "`n== $msg ==" -ForegroundColor Cyan }
function Log($msg)   { Write-Host "▶ $msg"        -ForegroundColor Green }
function Warn($msg)  { Write-Host "! $msg"        -ForegroundColor Yellow }
function Fatal($msg) { Write-Host "✗ $msg"        -ForegroundColor Red; exit 1 }

function Get-RawUrl([string]$path) {
    "https://raw.githubusercontent.com/$OphaRepo/$OphaBranch/$path"
}

function Ensure-Admin {
    $current = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Warn "Élévation UAC nécessaire pour modifier hosts et hostname. Relance avec privilèges admin..."
        $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        Start-Process -FilePath PowerShell -Verb RunAs -ArgumentList $args
        exit 0
    }
}

function Require-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Fatal @"
Docker Desktop n'est pas installé.

  1. Téléchargez : https://www.docker.com/products/docker-desktop/
  2. Lancez l'installeur, redémarrez si demandé.
  3. Ouvrez Docker Desktop, attendez "Docker Desktop is running".
  4. Relancez ce script.
"@
    }

    try {
        docker info | Out-Null
    } catch {
        Fatal "Docker est installé mais le démon n'est pas démarré. Ouvrez Docker Desktop et relancez ce script."
    }
}

function Get-LatestVersion {
    if ($OphaVersion) { return $OphaVersion }
    # On lit latest.txt à la racine du repo public opha-releases (1 ligne :
    # "v0.1.0"). Le repo source d'Opha (privé) y pousse la nouvelle version
    # à chaque tag via .github/workflows/release.yml.
    $url = Get-RawUrl 'latest.txt'
    try {
        $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15
        $tag = $r.Content.Trim()
        if ($tag) { return $tag }
    } catch {}
    Fatal "Impossible de récupérer la dernière version Opha depuis $url. Vérifiez votre connexion ou attendez qu'une release soit publiée sur https://github.com/$OphaRepo/releases."
}

function New-RandomHex([int]$bytes) {
    $buf = New-Object byte[] $bytes
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buf)
    -join ($buf | ForEach-Object { $_.ToString('x2') })
}

function Generate-EnvFile([string]$version) {
    $pwd = New-RandomHex 32
    $now = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    @"
# Opha — fichier .env généré par l'installeur le $now
# CONSERVEZ CE FICHIER : sans POSTGRES_PASSWORD, vos backups sont inutilisables.

OPHA_VERSION=$version

POSTGRES_DB=opha
POSTGRES_USER=opha
POSTGRES_PASSWORD=$pwd

OPHA_PUBLIC_HOST=$OphaHostname
CORS_ALLOWED_ORIGINS=https://$OphaHostname

REMEMBER_ME_VALIDITY_SECONDS=5184000
"@ | Out-File -FilePath (Join-Path $OphaHome '.env') -Encoding ascii
}

function Ensure-HostsEntry {
    $hosts = "$env:WINDIR\System32\drivers\etc\hosts"
    $line  = "127.0.0.1 $OphaHostname"
    $existing = Select-String -Path $hosts -Pattern "^\s*127\.0\.0\.1\s+$([regex]::Escape($OphaHostname))(\s|$)" -Quiet
    if ($existing) {
        Log "Entrée hosts $OphaHostname déjà présente."
        return
    }
    Warn "Ajout de '$line' à $hosts."
    Add-Content -Path $hosts -Value "`r`n$line"
}

function Ensure-Hostname {
    $current = $env:COMPUTERNAME
    if ($current -ieq 'opha') {
        Log "Nom d'ordinateur déjà 'opha'."
        return
    }
    Warn "Renommage du PC en 'opha' (effectif après reboot)."
    Rename-Computer -NewName 'opha' -Force -ErrorAction SilentlyContinue | Out-Null
}

function Wait-ForBackend {
    $timeoutSec = 120
    $elapsed = 0
    Log "Attente que le backend réponde (jusqu'à $timeoutSec s)..."
    while ($elapsed -lt $timeoutSec) {
        try {
            # ServerCertificateValidationCallback bypass pour le cert auto-signé Caddy.
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
            $r = Invoke-WebRequest -Uri "https://$OphaHostname/api/v1/health" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
            if ($r.Content -match '"status":"UP"') {
                Log "Backend prêt."
                return
            }
        } catch {}
        Start-Sleep -Seconds 3
        $elapsed += 3
    }
    Warn "Le backend ne répond pas encore. Vérifiez avec 'docker compose -f $OphaHome\docker-compose.prod.yml ps'."
}

function Create-DesktopShortcut {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $linkPath = Join-Path $desktop 'Ouvrir Opha.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($linkPath)
    $shortcut.TargetPath = "https://$OphaHostname"
    $shortcut.Save()
    Log "Raccourci créé : $linkPath"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

Step "Vérification de l'environnement"
Ensure-Admin
Require-Docker

Step "Création du dossier d'install"
New-Item -ItemType Directory -Force -Path (Join-Path $OphaHome 'caddy') | Out-Null
Log "Dossier : $OphaHome"

Step "Téléchargement des fichiers de configuration"
Invoke-WebRequest -Uri (Get-RawUrl 'docker-compose.prod.yml') -OutFile (Join-Path $OphaHome 'docker-compose.prod.yml') -UseBasicParsing
Invoke-WebRequest -Uri (Get-RawUrl 'caddy/Caddyfile')         -OutFile (Join-Path $OphaHome 'caddy\Caddyfile')        -UseBasicParsing
Log "docker-compose.prod.yml + caddy/Caddyfile téléchargés."

Step "Récupération de la dernière version Opha publiée"
$Version = Get-LatestVersion
Log "Version : $Version"

Step "Génération du fichier .env"
Generate-EnvFile -version $Version
Log "$OphaHome\.env créé."

Step "Configuration réseau locale"
Ensure-HostsEntry
Ensure-Hostname

Step "Pull des images Docker (peut prendre quelques minutes)"
Push-Location $OphaHome
try {
    & docker compose -f docker-compose.prod.yml --env-file .env pull
} finally {
    Pop-Location
}

Step "Démarrage de la stack Opha"
Push-Location $OphaHome
try {
    & docker compose -f docker-compose.prod.yml --env-file .env up -d
} finally {
    Pop-Location
}

Wait-ForBackend
Create-DesktopShortcut

Step "Installation terminée"
@"
Opha est maintenant accessible sur https://$OphaHostname

Au premier accès, votre navigateur affichera un avertissement de sécurité
(certificat auto-signé). Cliquez sur "Paramètres avancés" puis "Continuer
vers $OphaHostname" — c'est attendu.

Vous serez ensuite guidé par le wizard de premier compte (3 étapes).

Commandes utiles (depuis $OphaHome) :
  - Arrêter Opha     : docker compose -f docker-compose.prod.yml --env-file .env down
  - Redémarrer Opha  : docker compose -f docker-compose.prod.yml --env-file .env up -d
  - Voir les logs    : docker compose -f docker-compose.prod.yml --env-file .env logs -f
  - Mettre à jour    : .\update-opha.ps1
  - Désinstaller     : .\uninstall-opha.ps1
"@ | Write-Host

Start-Process "https://$OphaHostname"
