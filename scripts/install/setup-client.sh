#!/usr/bin/env bash
# Opha — configuration d'un PC client (Linux) — packaging V1 / P.3.
# Logique identique à la version macOS (cf. setup-client.command).

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
HOSTNAME="${OPHA_HOSTNAME:-opha.local}"
SERVER_IP="${1:-}"

if [[ -z "$SERVER_IP" ]]; then
    printf "${BOLD}Configuration du PC client pour atteindre Opha${NC}\n\n"
    read -rp "IP du serveur Opha : " SERVER_IP
fi

if ! [[ "$SERVER_IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
    printf "${RED}✗${NC} IP invalide : '$SERVER_IP'.\n" >&2
    exit 1
fi

target="$SERVER_IP $HOSTNAME"

if grep -qE "^[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+${HOSTNAME//./\\.}([[:space:]]|$)" /etc/hosts; then
    printf "${YELLOW}!${NC} Entrée hosts existante pour $HOSTNAME — remplacement (sudo demandé).\n"
    sudo sed -i.bak "/^[[:space:]]*[0-9]\{1,3\}\(\.[0-9]\{1,3\}\)\{3\}[[:space:]]\+${HOSTNAME//./\\.}\([[:space:]]\|$\)/d" /etc/hosts
fi

printf "${GREEN}▶${NC} Ajout de '$target' à /etc/hosts (sudo demandé).\n"
echo "$target" | sudo tee -a /etc/hosts >/dev/null

printf "\n${BOLD}Configuration terminée.${NC}\n"
printf "Ouvrez https://${HOSTNAME} dans votre navigateur.\n"
printf "Au 1er accès, acceptez l'avertissement de sécurité (cert auto-signé Caddy).\n\n"
