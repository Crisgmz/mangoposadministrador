#!/usr/bin/env bash
# Despliega Edge Functions de la CONSOLA (supabase/functions de este repo) al
# Supabase self-hosted de Coolify — el mismo stack que usa mangospos.
#
# Adaptado de mangospos/scripts/deploy_edge_functions.sh, con dos diferencias:
#   * NO sube `_shared/`: ese directorio es de mangospos y lo usan sus
#     funciones azul-*. Las funciones de este repo son autocontenidas.
#   * Hay que nombrar las funciones: sin argumentos no despliega nada.
#
# Igual que el original: identifica el contenedor POR EL VOLUMEN que monta (el
# host corre más de un stack), respalda antes de copiar, rsync SIN --delete
# (el volumen tiene funciones de otros repos) y reinicia el edge runtime.
#
# Uso:
#   ./scripts/deploy_edge_functions.sh admin-azul-refund
#   DRY=1 ./scripts/deploy_edge_functions.sh admin-azul-refund   # solo muestra qué cambiaría
#   VPS=root@otra.ip SERVICE=<id> ./scripts/deploy_edge_functions.sh admin-azul-refund

set -euo pipefail

VPS="${VPS:-root@31.97.40.114}"
SERVICE="${SERVICE:-n84o0s8s0w08cko8c48gsog4}"
REMOTE="/data/coolify/services/${SERVICE}/volumes/functions"
DRY="${DRY:-0}"

FUNCS=("$@")
if [[ ${#FUNCS[@]} -eq 0 ]]; then
  echo "Uso: $0 <funcion> [funcion...]   (ej: admin-azul-refund)" >&2
  exit 1
fi

cd "$(dirname "$0")/.."
LOCAL="supabase/functions"

for f in "${FUNCS[@]}"; do
  [[ -d "$LOCAL/$f" ]] || { echo "ERROR: no existe $LOCAL/$f" >&2; exit 1; }
  [[ "$f" == "_shared" ]] && { echo "ERROR: _shared es de mangospos; no se despliega desde aquí." >&2; exit 1; }
done

echo "VPS:       $VPS"
echo "Destino:   $REMOTE"
echo "Funciones: ${FUNCS[*]}"
echo

CTRL="/tmp/mangopos-admin-deploy-$$.sock"
cleanup() { ssh -S "$CTRL" -O exit "$VPS" 2>/dev/null || true; }
trap cleanup EXIT

echo "Abriendo conexion SSH (te va a pedir la clave una sola vez)..."
ssh -M -S "$CTRL" -o ControlPersist=10m -fN "$VPS"
SSH=(ssh -S "$CTRL" "$VPS")

RSYNC_OPTS=(-rcvz --exclude '*_test.ts' --exclude '.env*' -e "ssh -S $CTRL")

"${SSH[@]}" "test -d '$REMOTE'" || {
  echo "ERROR: $REMOTE no existe en el VPS. Revisa SERVICE." >&2
  exit 1
}

if [[ "$DRY" == "1" ]]; then
  echo "(DRY=1) Archivos que cambiarían (<f = se copia):"
  for f in "${FUNCS[@]}"; do
    rsync -n --itemize-changes "${RSYNC_OPTS[@]}" "$LOCAL/$f/" "$VPS:$REMOTE/$f/"
  done
  exit 0
fi

echo "Buscando el contenedor que monta ese volumen..."
CONTAINER=$("${SSH[@]}" bash -s <<REMOTE_EOF
for c in \$(docker ps --format '{{.Names}}'); do
  if docker inspect -f '{{range .Mounts}}{{.Source}} {{end}}' "\$c" 2>/dev/null | grep -q '$REMOTE'; then
    echo "\$c"
  fi
done
REMOTE_EOF
)
CONTAINER=$(echo "$CONTAINER" | head -1)
if [[ -z "$CONTAINER" ]]; then
  echo "ERROR: ningun contenedor monta $REMOTE. ¿Stack apagado o id equivocado?" >&2
  exit 1
fi
echo "Contenedor: $CONTAINER"
echo

# Respaldo de lo que exista hoy de esas funciones (en un primer deploy no hay nada).
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="/tmp/functions-admin-backup-${STAMP}.tgz"
EXISTING=$("${SSH[@]}" "cd '$REMOTE' && for f in ${FUNCS[*]}; do [ -d \"\$f\" ] && echo \"\$f\"; done" || true)
if [[ -n "$EXISTING" ]]; then
  "${SSH[@]}" "cd '$REMOTE' && tar czf '$BACKUP' $EXISTING"
  echo "Respaldo: $BACKUP"
  echo "Rollback: ssh $VPS \"cd $REMOTE && tar xzf $BACKUP && docker restart $CONTAINER\""
else
  echo "Primer deploy de ${FUNCS[*]}: no hay nada que respaldar."
  echo "Rollback: ssh $VPS \"cd $REMOTE && rm -rf ${FUNCS[*]} && docker restart $CONTAINER\""
fi
echo

for f in "${FUNCS[@]}"; do
  echo "→ $f"
  rsync "${RSYNC_OPTS[@]}" "$LOCAL/$f/" "$VPS:$REMOTE/$f/"
done

echo
echo "Reiniciando $CONTAINER..."
"${SSH[@]}" "docker restart '$CONTAINER'" >/dev/null
sleep 4

echo
echo "── Ultimas lineas del log ──"
"${SSH[@]}" "docker logs --tail 15 '$CONTAINER' 2>&1" || true

echo
echo "Listo. Verifica que arranque (sin token debe responder 401):"
for f in "${FUNCS[@]}"; do
  echo "  curl -s -X POST https://supabase.mangopos.do/functions/v1/$f"
done
