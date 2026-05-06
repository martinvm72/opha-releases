#!/usr/bin/env bash
# =============================================================================
# Opha — configuration d'un PC client (macOS) — packaging V1 / P.3
# =============================================================================
# À exécuter sur les PC du cabinet (autres que le serveur Mac mini) pour
# qu'ils puissent atteindre Opha via https://opha.local.
#
# Sur macOS et Windows 10 1803+, mDNS suffit normalement (pas de config
# requise). Ce script est un fallback pour les cas où mDNS ne marche pas
# (réseau ségrégé, Avahi désactivé, etc.) : il ajoute l'IP du serveur dans
# /etc/hosts.
#
# Usage : bash setup-client.command [IP_DU_SERVEUR]
# Si IP_DU_SERVEUR n'est pas passée en argument, le script demande à
# l'utilisateur.
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
HOSTNAME="${OPHA_HOSTNAME:-opha.local}"

SERVER_IP="${1:-}"

if [[ -z "$SERVER_IP" ]]; then
    printf "${BOLD}Configuration du PC client pour atteindre Opha${NC}\n\n"
    printf "Tapez d'abord ${BOLD}arp -a | grep opha${NC} sur le serveur Mac mini pour\n"
    printf "obtenir son IP locale (ou utilisez l'IP affichée dans les Préférences\n"
    printf "Système > Réseau du serveur).\n\n"
    read -rp "IP du serveur Opha : " SERVER_IP
fi

# Validation rudimentaire IPv4.
if ! [[ "$SERVER_IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
    printf "${RED}✗${NC} IP invalide : '$SERVER_IP'.\n" >&2
    exit 1
fi

target="$SERVER_IP $HOSTNAME"

# Si une autre entrée existe déjà pour ce hostname, on la supprime puis on rajoute.
if grep -qE "^[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+${HOSTNAME//./\\.}([[:space:]]|$)" /etc/hosts; then
    printf "${YELLOW}!${NC} Entrée hosts existante pour $HOSTNAME — remplacement (sudo demandé).\n"
    sudo sed -i.bak "/^[[:space:]]*[0-9]\{1,3\}\(\.[0-9]\{1,3\}\)\{3\}[[:space:]]\+${HOSTNAME//./\\.}\([[:space:]]\|$\)/d" /etc/hosts
fi

printf "${GREEN}▶${NC} Ajout de '$target' à /etc/hosts (sudo demandé).\n"
echo "$target" | sudo tee -a /etc/hosts >/dev/null

printf "\n${BOLD}Configuration terminée.${NC}\n"
printf "Ouvrez https://${HOSTNAME} dans votre navigateur.\n"
printf "Au 1er accès, acceptez l'avertissement de sécurité (cert auto-signé Caddy).\n\n"
