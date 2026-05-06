#!/usr/bin/env bash
# Opha — désinstalleur Linux — packaging V1 / P.3.
# Logique identique à la version macOS (cf. uninstall-opha.command).

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
OPHA_HOME="${OPHA_HOME:-$HOME/Opha}"

[[ -f "$OPHA_HOME/docker-compose.prod.yml" ]] || {
    printf "${RED}✗${NC} Aucune installation Opha détectée à $OPHA_HOME.\n" >&2
    exit 1
}

printf "\n${BOLD}== Désinstallation d'Opha ==${NC}\n\n"

cd "$OPHA_HOME"

printf "${GREEN}▶${NC} Arrêt de la stack...\n"
docker compose -f docker-compose.prod.yml --env-file .env down

# Désactivation du service systemd si installé.
if [[ -f /etc/systemd/system/opha.service ]]; then
    printf "${GREEN}▶${NC} Désactivation du service systemd opha.service (sudo demandé)...\n"
    sudo systemctl disable --now opha.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/opha.service
    sudo systemctl daemon-reload
fi

printf "\n${YELLOW}Voulez-vous SUPPRIMER les données Opha ?${NC}\n"
printf "  - Base Postgres (patients, consultations, prescriptions, etc.)\n"
printf "  - Documents patient (PDF, OCT, courriers)\n"
printf "  - Keystore eHealth\n"
printf "  - Certificats Caddy\n"
printf "${RED}Cette opération est irréversible.${NC}\n"
read -rp "Tapez 'OUI EFFACER' pour confirmer (autre chose = annuler) : " confirm

if [[ "$confirm" == "OUI EFFACER" ]]; then
    printf "${RED}▶${NC} Suppression des volumes...\n"
    docker compose -f docker-compose.prod.yml --env-file .env down -v
    printf "${GREEN}▶${NC} Volumes Opha supprimés.\n"
else
    printf "${GREEN}▶${NC} Volumes préservés. Vous pourrez les retrouver avec 'docker volume ls | grep opha_'.\n"
fi

read -rp "Supprimer aussi le dossier $OPHA_HOME/ ? [o/N] : " rmdir
if [[ "$rmdir" =~ ^[oOyY]$ ]]; then
    cd /
    rm -rf "$OPHA_HOME"
    printf "${GREEN}▶${NC} Dossier supprimé.\n"
fi

read -rp "Retirer l'entrée 127.0.0.1 opha.local de /etc/hosts ? [o/N] : " rmhosts
if [[ "$rmhosts" =~ ^[oOyY]$ ]]; then
    sudo sed -i.bak '/^[[:space:]]*127\.0\.0\.1[[:space:]]\+opha\.local\([[:space:]]\|$\)/d' /etc/hosts
    printf "${GREEN}▶${NC} /etc/hosts nettoyé (backup : /etc/hosts.bak).\n"
fi

printf "\n${BOLD}Désinstallation terminée.${NC}\n\n"
