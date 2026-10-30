#!/bin/sh
# Abre Grafana (logs y métricas) en http://localhost:3000 con un port-forward al Service del clúster.
# Imprime el usuario y la contraseña del Secret `grafana` (la genera el chart; nunca está en git ni en el estado).
# Uso:  scripts/grafana.sh [puerto-local]      Ctrl+C para cerrar.
set -eu

NS=${GRAFANA_NAMESPACE:-monitoring}
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

echo "Grafana:    http://localhost:$PUERTO"
echo "Usuario:    $usuario"
echo "Contraseña: $clave"
echo "Dashboards: carpeta «Solventa» → «Logs de servicios» y «Servicios (métricas)»"
echo

exec kubectl -n "$NS" port-forward svc/grafana "$PUERTO:80"
