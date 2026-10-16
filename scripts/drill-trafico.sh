#!/bin/sh
# Genera tráfico constante de cotizaciones durante el drill HA04 (US5) y registra cada resultado.
# Requiere un port-forward activo:  kubectl -n staging port-forward svc/solventa-backend 8000:80
#
# Uso: scripts/drill-trafico.sh [url_base] [segundos] [intervalo_s]
#   url_base    por defecto http://localhost:8000
#   segundos    duración total (por defecto 600)
#   intervalo_s pausa entre peticiones (por defecto 1)
#
# Salida: una línea por petición "<ISO-8601> <código_http> <cliente_id>" y un resumen al final.
# Los errores consecutivos delimitan la ventana de indisponibilidad; los cliente_id con 201 son
# las cotizaciones confirmadas que se contrastan con la base de datos para detectar pérdidas.
set -eu

BASE_URL="${1:-http://localhost:8000}"
DURATION="${2:-600}"
INTERVAL="${3:-1}"
RUN_ID="drill-$(date -u +%Y%m%d%H%M%S)"
LOG="${LOG:-drill-trafico-$RUN_ID.log}"

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: se requiere curl." >&2
  exit 2
fi

end=$(( $(date +%s) + DURATION ))
n=0
ok=0
err=0

echo "Registro: $LOG (run $RUN_ID)"
while [ "$(date +%s)" -lt "$end" ]; do
  n=$((n + 1))
  cliente="$RUN_ID-$n"
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
    -X POST "$BASE_URL/v1/cotizaciones" \
    -H 'Content-Type: application/json' \
    -d "{\"cliente_id\":\"$cliente\",\"producto\":\"microseguro_vida\",\"datos\":{\"edad\":35,\"suma_asegurada\":50000000}}" \
    || true)
  [ -n "$code" ] || code=000
  printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$code" "$cliente" >> "$LOG"
  if [ "$code" = "201" ]; then
    ok=$((ok + 1))
  else
    err=$((err + 1))
  fi
  sleep "$INTERVAL"
done

echo "Peticiones: $n  confirmadas (201): $ok  con error: $err"
echo "Para contar cotizaciones persistidas:"
echo "  SELECT count(*) FROM cotizacion.cotizaciones WHERE cliente_id LIKE '$RUN_ID-%';"
echo "Debe igualar las confirmadas ($ok): cualquier diferencia son cotizaciones perdidas."
