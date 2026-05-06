#!/usr/bin/env bash
# =============================================================================
# Opha — installeur Linux (packaging V1 / P.3)
# =============================================================================
# Compatible Ubuntu/Debian (apt), Fedora/RHEL (dnf), Arch (pacman) pour la
# détection Docker. Le reste est POSIX bash.
#
# Logique : cf. install-opha.command (la doc complète y est).
#
# Lancer :  bash install-opha.sh
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

OPHA_REPO="${OPHA_REPO:-martinvm72/opha-releases}"
OPHA_BRANCH="${OPHA_BRANCH:-main}"
OPHA_HOME="${OPHA_HOME:-$HOME/Opha}"
OPHA_HOSTNAME="${OPHA_HOSTNAME:-opha.local}"

raw_url() {
    echo "https://raw.githubusercontent.com/${OPHA_REPO}/${OPHA_BRANCH}/$1"
}

# Override `OPHA_VERSION` si l'utilisateur l'a forcée (ex. pour tester une
# version spécifique sans interroger latest.txt).
OPHA_VERSION_OVERRIDE="${OPHA_VERSION:-}"

log()   { printf "${GREEN}▶${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}!${NC} %s\n" "$*" >&2; }
fatal() { printf "${RED}✗${NC} %s\n" "$*" >&2; exit 1; }
step()  { printf "\n${BOLD}== %s ==${NC}\n" "$*"; }

require_linux() {
    [[ "$(uname -s)" == "Linux" ]] \
        || fatal "Ce script est destiné à Linux. Utilisez install-opha.command sous macOS ou install-opha.ps1 sous Windows."
}

suggest_docker_install() {
    if command -v apt >/dev/null; then
        echo "  sudo apt update && sudo apt install -y docker.io docker-compose-plugin"
        echo "  sudo systemctl enable --now docker"
        echo "  sudo usermod -aG docker \$USER && newgrp docker"
    elif command -v dnf >/dev/null; then
        echo "  sudo dnf install -y docker docker-compose-plugin"
        echo "  sudo systemctl enable --now docker"
        echo "  sudo usermod -aG docker \$USER && newgrp docker"
    elif command -v pacman >/dev/null; then
        echo "  sudo pacman -S docker docker-compose"
        echo "  sudo systemctl enable --now docker"
        echo "  sudo usermod -aG docker \$USER && newgrp docker"
    else
        echo "  Suivez https://docs.docker.com/engine/install/ pour votre distribution."
    fi
}

require_docker() {
    if ! command -v docker >/dev/null; then
        cat >&2 <<EOF

${RED}Docker n'est pas installé.${NC} Suggestion pour votre distribution :

$(suggest_docker_install)

Puis relancez ce script.
EOF
        exit 1
    fi

    if ! docker info >/dev/null 2>&1; then
        fatal "Docker est installé mais le démon n'est pas démarré. Lancez 'sudo systemctl start docker' et vérifiez votre appartenance au groupe 'docker'."
    fi
}

fetch_latest_version() {
    if [[ -n "$OPHA_VERSION_OVERRIDE" ]]; then
        echo "$OPHA_VERSION_OVERRIDE"
        return 0
    fi
    # On lit `latest.txt` à la racine du repo public opha-releases. Le repo
    # source d'Opha (privé) y pousse la nouvelle version à chaque tag via
    # le workflow .github/workflows/release.yml.
    local url
    url=$(raw_url latest.txt)
    local tag
    tag=$(curl -fsSL --max-time 15 "$url" | tr -d '[:space:]' || echo "")
    if [[ -z "$tag" ]]; then
        fatal "Impossible de récupérer la dernière version Opha depuis $url. Vérifiez votre connexion ou attendez qu'une release soit publiée sur https://github.com/${OPHA_REPO}/releases."
    fi
    echo "$tag"
}

generate_env() {
    local version="$1"
    local pwd
    pwd=$(openssl rand -hex 32)

    cat > "$OPHA_HOME/.env" <<EOF
# Opha — fichier .env généré par l'installeur le $(date +%Y-%m-%dT%H:%M:%S)
# CONSERVEZ CE FICHIER : sans POSTGRES_PASSWORD, vos backups sont inutilisables.

OPHA_VERSION=${version}

POSTGRES_DB=opha
POSTGRES_USER=opha
POSTGRES_PASSWORD=${pwd}

OPHA_PUBLIC_HOST=${OPHA_HOSTNAME}
CORS_ALLOWED_ORIGINS=https://${OPHA_HOSTNAME}

REMEMBER_ME_VALIDITY_SECONDS=5184000
EOF
    chmod 600 "$OPHA_HOME/.env"
}

ensure_hosts_entry() {
    local target="127.0.0.1 ${OPHA_HOSTNAME}"
    if grep -qE "^[[:space:]]*127\.0\.0\.1[[:space:]]+${OPHA_HOSTNAME//./\\.}([[:space:]]|$)" /etc/hosts; then
        log "Entrée hosts ${OPHA_HOSTNAME} déjà présente."
        return 0
    fi
    warn "Ajout de '${target}' à /etc/hosts (sudo demandé)."
    echo "$target" | sudo tee -a /etc/hosts >/dev/null
}

ensure_hostname() {
    local current
    current=$(hostname)
    if [[ "$current" == "opha" ]]; then
        log "Hostname machine déjà configuré sur 'opha'."
        return 0
    fi
    warn "Configuration du hostname machine en 'opha' (sudo demandé)."
    sudo hostnamectl set-hostname opha 2>/dev/null || sudo hostname opha 2>/dev/null || true
}

wait_for_backend() {
    local timeout=120
    local elapsed=0
    log "Attente que le backend réponde (jusqu'à ${timeout} s)..."
    while (( elapsed < timeout )); do
        if curl -sk --max-time 3 "https://${OPHA_HOSTNAME}/api/v1/health" 2>/dev/null | grep -q '"status":"UP"'; then
            log "Backend prêt."
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    warn "Le backend ne répond pas encore. Vérifiez avec 'docker compose -f $OPHA_HOME/docker-compose.prod.yml ps'."
}

install_systemd_service() {
    [[ "$EUID" -eq 0 ]] || command -v sudo >/dev/null || return 0
    [[ -d /etc/systemd/system ]] || return 0

    local sudo_cmd=""
    [[ "$EUID" -eq 0 ]] || sudo_cmd="sudo"

    local svc=/etc/systemd/system/opha.service
    if [[ -f "$svc" ]]; then
        log "Service systemd opha.service déjà installé."
        return 0
    fi
    warn "Installation du service systemd opha.service (sudo demandé)."
    $sudo_cmd tee "$svc" >/dev/null <<EOF
[Unit]
Description=Opha — Logiciel de gestion de cabinet d'ophtalmologie
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${OPHA_HOME}
EnvironmentFile=${OPHA_HOME}/.env
ExecStart=/usr/bin/docker compose -f docker-compose.prod.yml up -d
ExecStop=/usr/bin/docker compose -f docker-compose.prod.yml down
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
EOF
    $sudo_cmd systemctl daemon-reload
    $sudo_cmd systemctl enable opha.service
    log "Service installé. Démarrage automatique au boot configuré."
}

create_desktop_shortcut() {
    local desktop_dir
    desktop_dir=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
    [[ -d "$desktop_dir" ]] || return 0
    local target="$desktop_dir/Ouvrir Opha.desktop"
    cat > "$target" <<EOF
[Desktop Entry]
Type=Application
Name=Ouvrir Opha
Exec=xdg-open https://${OPHA_HOSTNAME}
Terminal=false
Icon=web-browser
EOF
    chmod +x "$target"
    log "Raccourci créé : ${target}"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

step "Vérification de l'environnement"
require_linux
require_docker

step "Création du dossier d'install"
mkdir -p "$OPHA_HOME/caddy"
log "Dossier : $OPHA_HOME"

step "Téléchargement des fichiers de configuration"
curl -fL --max-time 60 -o "$OPHA_HOME/docker-compose.prod.yml" "$(raw_url docker-compose.prod.yml)"
curl -fL --max-time 60 -o "$OPHA_HOME/caddy/Caddyfile" "$(raw_url caddy/Caddyfile)"
log "docker-compose.prod.yml + caddy/Caddyfile téléchargés."

step "Récupération de la dernière version Opha publiée"
VERSION=$(fetch_latest_version)
log "Version : ${VERSION}"

step "Génération du fichier .env"
generate_env "$VERSION"
log "$OPHA_HOME/.env créé (mode 600)."

step "Configuration réseau locale"
ensure_hosts_entry
ensure_hostname

step "Pull des images Docker (peut prendre quelques minutes)"
(cd "$OPHA_HOME" && docker compose -f docker-compose.prod.yml --env-file .env pull)

step "Démarrage de la stack Opha"
(cd "$OPHA_HOME" && docker compose -f docker-compose.prod.yml --env-file .env up -d)

step "Installation du service systemd (auto-start au boot)"
install_systemd_service

wait_for_backend
create_desktop_shortcut

step "Installation terminée"
cat <<EOF
${BOLD}Opha est maintenant accessible sur https://${OPHA_HOSTNAME}${NC}

Au premier accès, votre navigateur affichera un avertissement de sécurité
(certificat auto-signé). Cliquez sur "Avancé" puis "Accepter le risque" —
c'est attendu.

Vous serez ensuite guidé par le wizard de premier compte (3 étapes).

Commandes utiles (depuis $OPHA_HOME) :
  - Arrêter Opha     : docker compose -f docker-compose.prod.yml --env-file .env down
  - Redémarrer Opha  : docker compose -f docker-compose.prod.yml --env-file .env up -d
  - Voir les logs    : docker compose -f docker-compose.prod.yml --env-file .env logs -f
  - Mettre à jour    : bash update-opha.sh
  - Désinstaller     : bash uninstall-opha.sh

EOF

xdg-open "https://${OPHA_HOSTNAME}" 2>/dev/null || true
