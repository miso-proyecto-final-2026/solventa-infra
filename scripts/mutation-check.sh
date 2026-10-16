#!/bin/sh
# Comprobación de mutaciones (SC-006): cada parche de tests/mutations rompe una regla de FR-030 y
# `terraform test` DEBE fallar al aplicarlo. Si una mutación sobrevive, la prueba no protege la regla.
#
# Uso:  scripts/mutation-check.sh [parche ...]
# Salida: 0 si todas las mutaciones fueron detectadas; 1 si alguna sobrevivió; 2 si falta alguna herramienta.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

for tool in terraform patch tar; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: falta la herramienta '$tool'." >&2
    exit 2
  fi
done

if [ "$#" -gt 0 ]; then
  patches="$*"
else
  patches=$(ls tests/mutations/*.patch)
fi

survivors=0
detected=0

for p in $patches; do
  name=$(basename "$p" .patch)
  rule=$(sed -n 's/^# rule: //p' "$p" | head -n 1)
  dirs=$(sed -n 's/^# tests: //p' "$p" | head -n 1)
  if [ -z "$dirs" ]; then
    dirs="bootstrap environments/staging/platform environments/staging/baseline $(ls -d modules/*)"
  fi

  tmp=$(mktemp -d)
  # Copia de trabajo sin estado de Terraform ni historial git.
  tar --exclude=.git --exclude=.terraform --exclude='*.tfstate*' -cf - . | (cd "$tmp" && tar -xf -)

  if ! (cd "$tmp" && patch -p1 -s < "$ROOT/$p"); then
    echo "ERROR  $name: el parche no se aplica"
    rm -rf "$tmp"
    survivors=$((survivors + 1))
    continue
  fi

  caught=0
  for d in $dirs; do
    [ -d "$tmp/$d/tests" ] || continue
    (cd "$tmp/$d" && terraform init -backend=false -input=false >/dev/null 2>&1) || {
      echo "ERROR  $name: terraform init falló en $d" >&2
      continue
    }
    if out=$(cd "$tmp/$d" && terraform test -no-color 2>&1); then
      :
    else
      caught=1
      msg=$(printf '%s\n' "$out" | grep -m 1 -E 'RULE|Test assertion failed|Invalid|Error' || true)
      echo "OK     $name -> detectada en $d  [${rule:-regla sin nombre}] ${msg}"
      break
    fi
  done

  if [ "$caught" -eq 1 ]; then
    detected=$((detected + 1))
  else
    echo "SOBREVIVE  $name: ninguna prueba falló con la mutación [${rule:-regla sin nombre}]" >&2
    survivors=$((survivors + 1))
  fi

  rm -rf "$tmp"
done

echo "Mutaciones detectadas: $detected; sobrevivientes: $survivors"
[ "$survivors" -eq 0 ]
