#!/usr/bin/env bash
# Opha — mise à jour manuelle (Linux) — packaging V1 / P.3.

set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
OPHA_HOME="${OPHA_HOME:-$HOME/Opha}"

[[ -f "$OPHA_HOME/.env" ]] || {
    printf "${RED}✗${NC} Aucune installation Opha détectée à $OPHA_HOME.\n   Lancez d'abord install-opha.sh.\n" >&2
    exit 1
}

cd "$OPHA_HOME"
printf "\n${BOLD}== Mise à jour d'Opha ==${NC}\n"
printf "${GREEN}▶${NC} Pull des images...\n"
docker compose -f docker-compose.prod.yml --env-file .env pull

printf "${GREEN}▶${NC} Redémarrage de la stack...\n"
docker compose -f docker-compose.prod.yml --env-file .env up -d

printf "\n${BOLD}Mise à jour terminée.${NC} Vérifiez https://opha.local\n\n"
