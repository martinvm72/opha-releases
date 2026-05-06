#!/usr/bin/env bash
# =============================================================================
# Opha — installeur macOS (packaging V1 / P.3)
# =============================================================================
# Double-cliquable depuis Finder (extension .command).
#
# Que fait ce script :
#   1. Vérifie que Docker Desktop est installé et en cours d'exécution.
#   2. Crée ~/Opha/ comme dossier d'install.
#   3. Télécharge docker-compose.prod.yml et caddy/Caddyfile depuis le repo.
#   4. Génère .env avec un mot de passe Postgres aléatoire et la dernière
#      version d'Opha publiée sur GHCR.
#   5. Ajoute "127.0.0.1 opha.local" à /etc/hosts si nécessaire (sudo).
#   6. Configure le hostname machine en "opha" (scutil, sudo).
#   7. Pull les images depuis ghcr.io et démarre la stack.
#   8. Attend que le backend réponde puis ouvre le navigateur sur
#      https://opha.local — l'utilisateur arrive sur le wizard /setup.
#
# Si quelque chose foire, relancer ce script est sûr : tout est idempotent.
# =============================================================================

set -euo pipefail

# Couleurs (terminal macOS supporte ANSI par défaut).
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

step() { printf "\n${BOLD}== %s ==${NC}\n" "$*"; }

require_macos() {
    [[ "$(uname -s)" == "Darwin" ]] \
        || fatal "Ce script est destiné à macOS. Utilisez install-opha.sh sous Linux ou install-opha.ps1 sous Windows."
}

require_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        cat >&2 <<EOF

${RED}Docker Desktop n'est pas installé.${NC}

  1. Téléchargez Docker Desktop : https://www.docker.com/products/docker-desktop/
  2. Lancez l'installeur, puis ouvrez Docker (icône baleine dans la barre des menus).
  3. Attendez que Docker affiche "Docker Desktop is running".
  4. Relancez ce script.

EOF
        exit 1
    fi

    if ! docker info >/dev/null 2>&1; then
        fatal "Docker est installé mais le démon n'est pas démarré. Ouvrez Docker Desktop et relancez ce script."
    fi
}

fetch_latest_version() {
    if [[ -n "$OPHA_VERSION_OVERRIDE" ]]; then
        echo "$OPHA_VERSION_OVERRIDE"
        return 0
    fi
    # On lit `latest.txt` à la racine du repo public opha-releases (1 ligne :
    # "v0.1.0"). Le repo source d'Opha (privé) y pousse la nouvelle version
    # à chaque tag via .github/workflows/release.yml.
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
    current=$(scutil --get LocalHostName 2>/dev/null || echo "")
    if [[ "$current" == "opha" ]]; then
        log "Hostname machine déjà configuré sur 'opha'."
        return 0
    fi
    warn "Configuration du hostname machine en 'opha' (sudo demandé)."
    sudo scutil --set HostName opha 2>/dev/null || true
    sudo scutil --set LocalHostName opha 2>/dev/null || true
    sudo scutil --set ComputerName "Opha" 2>/dev/null || true
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
    warn "Le backend ne répond pas encore. Continuation tout de même — vous pouvez vérifier l'état avec 'docker compose -f $OPHA_HOME/docker-compose.prod.yml ps'."
}

create_desktop_shortcut() {
    local desktop="$HOME/Desktop"
    [[ -d "$desktop" ]] || return 0
    local target="$desktop/Ouvrir Opha.command"
    cat > "$target" <<EOF
#!/usr/bin/env bash
open "https://${OPHA_HOSTNAME}"
EOF
    chmod +x "$target"
    log "Raccourci créé : ${target}"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

step "Vérification de l'environnement"
require_macos
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

wait_for_backend
create_desktop_shortcut

step "Installation terminée"
cat <<EOF
${BOLD}Opha est maintenant accessible sur https://${OPHA_HOSTNAME}${NC}

Au premier accès, votre navigateur affichera un avertissement de sécurité
(certificat auto-signé). Cliquez sur "Avancé" puis "Continuer vers
${OPHA_HOSTNAME}" — c'est attendu.

Vous serez ensuite guidé par le wizard de premier compte (3 étapes).

Commandes utiles (depuis $OPHA_HOME) :
  - Arrêter Opha             : docker compose -f docker-compose.prod.yml --env-file .env down
  - Redémarrer Opha          : docker compose -f docker-compose.prod.yml --env-file .env up -d
  - Voir les logs            : docker compose -f docker-compose.prod.yml --env-file .env logs -f
  - Mettre à jour            : double-cliquez sur update-opha.command (à venir)
  - Désinstaller             : double-cliquez sur uninstall-opha.command

EOF

# Ouvre le navigateur sur le wizard.
open "https://${OPHA_HOSTNAME}" || true
