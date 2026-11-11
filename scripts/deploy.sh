#!/usr/bin/env bash
# Exécuté SUR l'instance EC2 (envoyé par CircleCI via : ssh ... "bash -s -- <env> <image> <port>" < scripts/deploy.sh)
#
# Prérequis sur l'EC2 (une seule fois) :
#   - Docker installé, l'utilisateur SSH dans le groupe docker
#   - Un fichier /etc/php-devops/<env>.env (chmod 600) contenant :
#       INFISICAL_CLIENT_ID=...        (Machine Identity, Universal Auth)
#       INFISICAL_CLIENT_SECRET=...
#       INFISICAL_PROJECT_ID=...
#       INFISICAL_API_URL=https://app.infisical.com/api   (ou https://eu.infisical.com/api)
set -euo pipefail

APP_ENV="${1:?env manquant (staging|prod)}"
IMAGE="${2:?image manquante}"
PORT="${3:?port manquant}"
NAME="php-devops-${APP_ENV}"
CONF="/etc/php-devops/${APP_ENV}.env"

[ -r "$CONF" ] || { echo "Fichier $CONF introuvable ou illisible"; exit 1; }

get_conf() { grep -E "^$1=" "$CONF" | head -n1 | cut -d= -f2-; }
PROJECT_ID="$(get_conf INFISICAL_PROJECT_ID)"
API_URL="$(get_conf INFISICAL_API_URL)"
API_URL="${API_URL:-https://app.infisical.com/api}"

echo ">> Pull de ${IMAGE}"
docker pull "$IMAGE"

echo ">> Obtention d'un access token Infisical (Machine Identity)"
TOKEN="$(docker run --rm --env-file "$CONF" --entrypoint sh "$IMAGE" -c \
  'infisical login --method=universal-auth --client-id="$INFISICAL_CLIENT_ID" --client-secret="$INFISICAL_CLIENT_SECRET" --domain="$INFISICAL_API_URL" --silent --plain')"
[ -n "$TOKEN" ] || { echo "Token Infisical vide"; exit 1; }

echo ">> Remplacement du conteneur ${NAME}"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d \
  --name "$NAME" \
  --restart unless-stopped \
  --security-opt no-new-privileges \
  --memory 256m --cpus 0.5 \
  -v "${NAME}-db:/var/www/html/database" \
  -p "${PORT}:80" \
  -e INFISICAL_TOKEN="$TOKEN" \
  -e INFISICAL_API_URL="$API_URL" \
  "$IMAGE" \
  infisical run --env="$APP_ENV" --projectId="$PROJECT_ID" --domain="$API_URL" -- apache2-foreground

echo ">> Vérification que l'application répond"
for i in $(seq 1 15); do
  if curl -fsS -o /dev/null "http://localhost:${PORT}/"; then
    echo "OK : ${NAME} répond sur le port ${PORT}"
    docker image prune -f >/dev/null
    exit 0
  fi
  sleep 2
done

echo "ECHEC : l'application ne répond pas"
docker logs --tail 50 "$NAME" || true
exit 1
