#!/bin/sh
# Grafana (logs y métricas). Imprime el usuario y la contraseña del Secret `grafana` (la genera el chart; nunca está en git
# ni en el estado) y, sin `--credenciales`, abre http://localhost:3000 con un port-forward al Service del clúster.
# Con Grafana publicado por el borde, la URL es la salida `grafana_url` de la etapa platform y basta con `--credenciales`.
# Uso:  scripts/grafana.sh [puerto-local]      Ctrl+C para cerrar.
#       scripts/grafana.sh --credenciales      solo imprime usuario y contraseña
set -eu

NS=${GRAFANA_NAMESPACE:-monitoring}
SOLO_CREDENCIALES=no
if [ "${1:-}" = "--credenciales" ]; then
  SOLO_CREDENCIALES=si
  shift
fi
PUERTO=${1:-3000}

for tool in kubectl base64; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Error: falta la herramienta '$tool'." >&2; exit 2; }
done

if ! kubectl -n "$NS" get svc grafana >/dev/null 2>&1; then
  echo "Error: no existe el Service grafana en el namespace $NS. ¿Está encendido staging y desplegado el baseline con enable_observability?" >&2
  exit 1
fi

usuario=$(kubectl -n "$NS" get secret grafana -o jsonpath='{.data.admin-user}' | base64 -d)
clave=$(kubectl -n "$NS" get secret grafana -o jsonpath='{.data.admin-password}' | base64 -d)

if [ "$SOLO_CREDENCIALES" = "si" ]; then
  echo "Usuario:    $usuario"
  echo "Contraseña: $clave"
  exit 0
fi

echo "Grafana:    http://localhost:$PUERTO"
echo "Usuario:    $usuario"
echo "Contraseña: $clave"
echo "Dashboards: carpeta «Solventa» → «Logs de servicios» y «Servicios (métricas)»"
echo

exec kubectl -n "$NS" port-forward svc/grafana "$PUERTO:80"
