# opha-releases

Installeurs publics et configuration de déploiement pour [**Opha**](https://github.com/martinvm72/Opha) — un logiciel de gestion de cabinet d'ophtalmologie pour la Belgique.

> Ce dépôt ne contient ni code source ni logique métier — uniquement les scripts d'installation et les manifestes Docker nécessaires pour déployer Opha sur une machine cabinet. Le code source reste privé. Les images binaires sont distribuées via GHCR (GitHub Container Registry).

## Installation rapide

### macOS

```bash
curl -fL https://raw.githubusercontent.com/martinvm72/opha-releases/main/scripts/install/install-opha.command -o install-opha.command
chmod +x install-opha.command
./install-opha.command
```

Ou téléchargez `install-opha.command` depuis [`scripts/install/`](./scripts/install/), faites un clic droit → **Ouvrir** depuis le Finder.

### Windows (PowerShell, terminal admin)

```powershell
iwr -useb https://raw.githubusercontent.com/martinvm72/opha-releases/main/scripts/install/install-opha.ps1 -OutFile install-opha.ps1
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\install-opha.ps1
```

### Linux

```bash
curl -fL https://raw.githubusercontent.com/martinvm72/opha-releases/main/scripts/install/install-opha.sh -o install-opha.sh
bash install-opha.sh
```

## Pré-requis

- **Docker Desktop** (Mac/Windows) ou **Docker Engine** (Linux), démarré.
- ~3 Go d'espace disque pour les images.
- Une connexion internet (uniquement à l'install et aux mises à jour).

## Que fait l'installeur ?

1. Vérifie que Docker tourne.
2. Crée `~/Opha/` (Mac/Linux) ou `C:\Users\<vous>\Opha\` (Windows).
3. Télécharge `docker-compose.prod.yml` et `caddy/Caddyfile` depuis ce dépôt.
4. Génère un `.env` avec un mot de passe Postgres aléatoire de 256 bits.
5. Ajoute `127.0.0.1 opha.local` dans `/etc/hosts` (sudo demandé).
6. Renomme la machine en `opha`.
7. Pull les images depuis GHCR et démarre la stack.
8. Ouvre votre navigateur sur `https://opha.local` → wizard de premier compte.

## Structure du dépôt

```
opha-releases/
├── README.md                       ← ce fichier
├── LICENSE.txt                     ← conditions d'usage (évaluation autorisée, prod sous licence)
├── latest.txt                      ← version Opha actuellement publiée (lue par les installeurs)
├── docker-compose.prod.yml         ← stack Docker prod (postgres + backend + frontend + caddy)
├── caddy/
│   └── Caddyfile                   ← config reverse-proxy + HTTPS auto-signé sur opha.local
└── scripts/install/                ← scripts d'install/update/uninstall pour Mac, Windows, Linux
```

## Gestion quotidienne

Une fois Opha installé, depuis le dossier d'install (`~/Opha/`) :

```bash
# Voir l'état
docker compose -f docker-compose.prod.yml --env-file .env ps

# Voir les logs
docker compose -f docker-compose.prod.yml --env-file .env logs -f

# Arrêter
docker compose -f docker-compose.prod.yml --env-file .env down

# Redémarrer
docker compose -f docker-compose.prod.yml --env-file .env up -d

# Mise à jour (l'admin a aussi un bouton "Installer maintenant" dans l'UI)
./update-opha.sh    # ou .command, ou .ps1
```

## Variables d'environnement (avancé)

Tous les installeurs respectent ces overrides (utiles pour les tests) :

| Variable | Défaut | Effet |
|---|---|---|
| `OPHA_REPO` | `martinvm72/opha-releases` | Repo source des manifestes (utile pour tester un fork) |
| `OPHA_BRANCH` | `main` | Branche pour le téléchargement raw |
| `OPHA_HOME` | `~/Opha` | Dossier d'install local |
| `OPHA_HOSTNAME` | `opha.local` | Hostname Caddy + entrée hosts |
| `OPHA_VERSION` | (lit `latest.txt`) | Force une version spécifique au lieu de la dernière |

## Licence

Voir [`LICENSE.txt`](./LICENSE.txt). En résumé : **évaluation autorisée, usage commercial / production réservé aux licenciés.** Pour toute demande de licence : `martinvanmollekot@gmail.com`.

## Support

- **Documentation utilisateur** : [docs Opha](https://github.com/martinvm72/Opha/tree/main/docs) (accès sur demande au repo privé).
- **Bugs et suggestions** : ouvrez une [issue](https://github.com/martinvm72/opha-releases/issues) ici (le repo `Opha` étant privé, les issues publiques se centralisent sur `opha-releases`).
