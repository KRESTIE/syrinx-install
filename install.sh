#!/bin/sh
# Syrinx — installation en une commande (NAS, Raspberry Pi, PC sous Linux), avec Docker.
#
#   curl -fsSL <adresse de ce fichier> | sh
#
# Ce que fait ce script, et rien d'autre :
#   1. vérifie que Docker (avec « docker compose ») est là ;
#   2. demande où est ta musique (une seule question, avec une proposition) ;
#   3. écrit compose.yml et .env dans un dossier « syrinx » (Navidrome + le serveur Syrinx) ;
#   4. lance les deux conteneurs, puis affiche l'adresse où finir l'installation (assistant dans le navigateur).
# Il ne touche pas à ta musique (lecture seule, sauf le sous-dossier Imports où vont les fichiers que tu ajoutes
# depuis Syrinx) et n'ouvre rien sur Internet.
#
# Options (toutes facultatives) :
#   --music <dossier>   dossier de la musique (sinon : question, avec une proposition)
#   --dir <dossier>     où ranger Syrinx (réglages et données) ; défaut : /volume1/docker/syrinx ou ~/syrinx
#   --port <n>          port de Syrinx web ; défaut : 8090, ou le suivant libre
#   --yes               aucune question : les propositions sont prises telles quelles
#   --dry-run           écrit les fichiers mais ne lance rien (tests)
# Variables : SYRINX_IMAGE (image du serveur), LANG (fr… = textes en français, sinon en anglais).
set -eu

IMAGE="${SYRINX_IMAGE:-ghcr.io/krestie/syrinx:public}"

MUSIC=""
DIR=""
PORT=""
YES=0
DRY=0

case "${LANG:-}${LC_ALL:-}" in
  fr*|*fr_*) FR=1 ;;
  *) FR=0 ;;
esac

# say "texte français" "English text"
say() { if [ "$FR" = 1 ]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi; }
fail() { say "Erreur : $1" "Error: $2" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --music) MUSIC="${2:-}"; shift 2 ;;
    --dir) DIR="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    --yes|-y) YES=1; shift ;;
    --dry-run) DRY=1; YES=1; shift ;;
    *) fail "option inconnue : $1" "unknown option: $1" ;;
  esac
done

# Question avec une proposition ; lue sur le terminal (le script lui-même arrive par « curl | sh »)
ask() {
  if [ "$YES" = 1 ] || [ ! -r /dev/tty ]; then printf '%s' "$2"; return; fi
  printf '%s [%s] ' "$1" "$2" > /dev/tty
  read -r answer < /dev/tty || answer=""
  printf '%s' "${answer:-$2}"
}

say "" ""
say "Syrinx — installation" "Syrinx — installation"
say "======================" "======================"

# ---------------------------------------------------------------- 1. Docker
if [ "$DRY" = 0 ]; then
  command -v docker >/dev/null 2>&1 || fail \
    "Docker n'est pas installé. Sur un NAS : installe « Docker » (ou « Container Manager ») depuis son centre d'applications. Sur Linux : https://docs.docker.com/engine/install/" \
    "Docker isn't installed. On a NAS: install \"Docker\" (or \"Container Manager\") from its app center. On Linux: https://docs.docker.com/engine/install/"
  docker compose version >/dev/null 2>&1 || fail \
    "« docker compose » est introuvable : mets Docker à jour (version 2 ou plus récente)." \
    "\"docker compose\" not found: update Docker (version 2 or newer)."
  docker info >/dev/null 2>&1 || fail \
    "Docker ne répond pas, ou il faut les droits administrateur : relance avec sudo (… | sudo sh)." \
    "Docker isn't responding, or admin rights are needed: run again with sudo (… | sudo sh)."
fi

# ---------------------------------------------------------------- 2. Musique
if [ -z "$MUSIC" ]; then
  guess=""
  H="${HOME:-/root}"
  if [ -n "${SUDO_USER:-}" ]; then H=$(getent passwd "$SUDO_USER" | cut -d: -f6); [ -n "$H" ] || H="${HOME:-/root}"; fi
  for d in /volume1/Musique /volume1/Music /volume1/music /share/Music /mnt/music /srv/music \
           "$H/Musique" "$H/Music"; do
    if [ -d "$d" ]; then guess="$d"; break; fi
  done
  [ -n "$guess" ] || guess="$H/Music"
  MUSIC=$(ask "$(say 'Dossier de ta musique ?' 'Where is your music?')" "$guess")
fi
# « ~/Music » tapé à la question : le shell ne l'a pas remplacé (et avec sudo, HOME est celui de root)
USER_HOME="$HOME"
if [ -n "${SUDO_USER:-}" ]; then USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6); fi
[ -n "$USER_HOME" ] || USER_HOME="${HOME:-/root}"
# shellcheck disable=SC2088  # on cherche justement le « ~ » tapé tel quel
case "$MUSIC" in "~") MUSIC="$USER_HOME" ;; "~/"*) MUSIC="$USER_HOME/${MUSIC#\~/}" ;; esac
case "$MUSIC" in /*) ;; *) MUSIC="$(pwd)/$MUSIC" ;; esac
MUSIC="${MUSIC%/}"
if [ ! -d "$MUSIC" ]; then
  mkdir -p "$MUSIC" || fail "impossible de créer $MUSIC" "cannot create $MUSIC"
  say "Dossier créé : $MUSIC (copie ta musique dedans)." "Folder created: $MUSIC (copy your music into it)."
fi

# ---------------------------------------------------------------- 3. Dossier de Syrinx, port, utilisateur
if [ -z "$DIR" ]; then
  if [ -d /volume1/docker ]; then DIR=/volume1/docker/syrinx; else DIR="${HOME:-/root}/syrinx"; fi
fi
case "$DIR" in /*) ;; *) DIR="$(pwd)/$DIR" ;; esac
DIR="${DIR%/}"

port_busy() {
  if command -v ss >/dev/null 2>&1; then ss -ltn 2>/dev/null | grep -q "[:.]$1 "
  elif command -v netstat >/dev/null 2>&1; then netstat -ltn 2>/dev/null | grep -q "[:.]$1 "
  else return 1; fi
}
if [ -z "$PORT" ]; then
  PORT=8090
  while port_busy "$PORT" && [ "$PORT" -lt 8100 ]; do PORT=$((PORT + 1)); done
fi

# Les fichiers créés par Syrinx appartiennent au propriétaire du dossier de musique (sinon à toi)
owner() { stat -c "%$1" "$MUSIC" 2>/dev/null || stat -f "%$1" "$MUSIC" 2>/dev/null || id "-$2"; }
PUID=$(owner u u)
PGID=$(owner g g)
[ "$PUID" != 0 ] || { PUID=$(id -u); PGID=$(id -g); }

TZ_NAME="${TZ:-}"
[ -n "$TZ_NAME" ] || TZ_NAME=$(cat /etc/timezone 2>/dev/null || true)
[ -n "$TZ_NAME" ] || TZ_NAME=$(readlink /etc/localtime 2>/dev/null | sed -n 's|.*/zoneinfo/||p')
[ -n "$TZ_NAME" ] || TZ_NAME=UTC

say "" ""
say "  Musique : $MUSIC (lecture seule)" "  Music:   $MUSIC (read-only)"
say "  Syrinx  : $DIR" "  Syrinx:  $DIR"
say "  Port    : $PORT" "  Port:    $PORT"
ok=$(ask "$(say 'On installe ? (o/n)' 'Install? (y/n)')" "$(say o y)")
case "$ok" in [oOyY]*) ;; *) say "Rien n'a été changé." "Nothing was changed."; exit 0 ;; esac

mkdir -p "$DIR/data/syrinx" "$DIR/data/navidrome" "$MUSIC/Imports"
if [ "$(id -u)" = 0 ]; then chown -R "$PUID:$PGID" "$DIR/data" "$MUSIC/Imports"; fi

# ---------------------------------------------------------------- 4. Fichiers
cat > "$DIR/.env" <<EOF
# Réglages de Syrinx (écrits par install.sh). Après un changement : docker compose up -d
MUSIC_PATH='$MUSIC'
DATA_PATH='$DIR/data'
PORT=$PORT
PUID=$PUID
PGID=$PGID
TZ=$TZ_NAME
SYRINX_IMAGE=$IMAGE
EOF

cat > "$DIR/compose.yml" <<'EOF'
# Syrinx (écrit par install.sh). Réglages : .env, à côté.
# Mise à jour :  docker compose pull && docker compose up -d
name: syrinx

services:
  navidrome:
    image: deluan/navidrome:0.64.2
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    # Aucun port ouvert : seul Syrinx parle à Navidrome (son compte est créé par l'assistant de Syrinx)
    environment:
      ND_SCANSCHEDULE: "1h"
      ND_SESSIONTIMEOUT: "168h"
      ND_ENABLETRANSCODINGCONFIG: "true"
      ND_SCANNER_PURGEMISSING: "full"
      TZ: "${TZ}"
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://127.0.0.1:4533/ping"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 1m
    volumes:
      - "${DATA_PATH}/navidrome:/data"
      - "${MUSIC_PATH}:/music:ro"
    logging: &logging
      driver: json-file
      options: {max-size: "10m", max-file: "3"}

  syrinx:
    image: "${SYRINX_IMAGE}"
    restart: unless-stopped
    depends_on:
      navidrome:
        condition: service_healthy
    ports:
      - "${PORT}:8090"
    environment:
      PUID: "${PUID}"
      PGID: "${PGID}"
      TZ: "${TZ}"
      NAVIDROME_URL: http://navidrome:4533
      NAVIDROME_DB: /navidrome/navidrome.db
      MUSIC_LABEL: "${MUSIC_PATH}"
    # Données rendues à PUID au démarrage, puis le serveur tourne avec ce compte (jamais root)
    command: ["sh", "-c", "chown $${PUID}:$${PGID} /data /music/Imports; exec setpriv --reuid=$${PUID} --regid=$${PGID} --clear-groups python web.py"]
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8090/healthz', timeout=10)"]
      interval: 1m
      timeout: 15s
      retries: 3
      start_period: 2m
    volumes:
      - "${MUSIC_PATH}:/music:ro"
      # « Ajouter des fichiers » (achats, CD numérisés) : le seul dossier où Syrinx peut écrire
      - "${MUSIC_PATH}/Imports:/music/Imports"
      - "${DATA_PATH}/syrinx:/data"
      - "${DATA_PATH}/navidrome:/navidrome"
    logging: *logging
EOF

say "" ""
say "Fichiers écrits dans $DIR." "Files written to $DIR."
if [ "$DRY" = 1 ]; then exit 0; fi

# ---------------------------------------------------------------- 5. Lancement
say "Téléchargement et démarrage (quelques minutes la première fois)…" "Downloading and starting (a few minutes the first time)…"
cd "$DIR" || exit 1
docker compose up -d || fail "le démarrage a échoué (détails ci-dessus)." "startup failed (details above)."

ip=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -n "$ip" ] || ip=$(ip route get 1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p')
[ -n "$ip" ] || ip=localhost

# Attente du serveur (Navidrome démarre d'abord)
i=0
while [ $i -lt 90 ]; do
  if docker compose exec -T syrinx python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8090/healthz', timeout=5)" >/dev/null 2>&1; then
    break
  fi
  i=$((i + 1)); sleep 2
done

say "" ""
say "C'est installé. Ouvre cette adresse pour finir (prénom, mot de passe, téléphone) :" \
    "Installed. Open this address to finish (name, password, phone):"
say "" ""
say "    http://$ip:$PORT/app/" "    http://$ip:$PORT/app/"
say "" ""
say "Depuis un appareil de ton réseau (chez toi)." "From a device on your home network."
