#!/bin/sh
# Prueba de humo del bus de eventos (HS2, criterio 4): desde un pod del clúster publica un evento en
# `solventa.humo` y lo consume de vuelta, autenticándose con la identidad de Pod Identity `kafka-humo`.
#
# Uso:  scripts/prueba-humo-kafka.sh [region]
# Requiere: AWS CLI y kubectl apuntando al clúster (aws eks update-kubeconfig), y baseline aplicado con el bus de eventos.
# Sale con 0 si el evento llegó; 1 si no; 2 si falta algo. No imprime credenciales: los brokers no son secretos.
set -eu

REGION="${1:-${AWS_REGION:-us-east-1}}"
CLUSTER_NAME="${CLUSTER_NAME:-solventa-staging}"
NAMESPACE="solventa-system"
DIR=$(cd "$(dirname "$0")" && pwd)
JOB="kafka-humo-$(date +%s)"

for tool in aws kubectl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Error: falta '$tool'." >&2; exit 2; }
done

arn=$(aws kafka list-clusters-v2 --region "$REGION" --cluster-name-filter "$CLUSTER_NAME-events" \
  --query "ClusterInfoList[0].ClusterArn" --output text 2>/dev/null || true)
if [ -z "$arn" ] || [ "$arn" = "None" ]; then
  echo "Error: no existe el clúster MSK $CLUSTER_NAME-events (¿platform con enable_events?)." >&2
  exit 2
fi
brokers=$(aws kafka get-bootstrap-brokers --region "$REGION" --cluster-arn "$arn" \
  --query "BootstrapBrokerStringSaslIam" --output text)
if [ -z "$brokers" ] || [ "$brokers" = "None" ]; then
  echo "Error: el clúster no entrega brokers SASL/IAM todavía (estado aún no ACTIVE)." >&2
  exit 2
fi

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || { echo "Error: falta el namespace $NAMESPACE (¿baseline aplicado?)." >&2; exit 2; }
kubectl -n "$NAMESPACE" get serviceaccount kafka-humo >/dev/null 2>&1 || kubectl -n "$NAMESPACE" create serviceaccount kafka-humo >/dev/null

limpiar() {
  kubectl -n "$NAMESPACE" delete job "$JOB" --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n "$NAMESPACE" delete configmap "$JOB" --ignore-not-found >/dev/null 2>&1 || true
}
trap limpiar EXIT

kubectl -n "$NAMESPACE" create configmap "$JOB" --from-file=humo.py="$DIR/humo-kafka/humo.py" >/dev/null

cat <<YAML | kubectl -n "$NAMESPACE" apply -f - >/dev/null
apiVersion: batch/v1
kind: Job
metadata:
  name: $JOB
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      serviceAccountName: kafka-humo
      containers:
        - name: humo
          image: python:3.12-slim
          command: ["sh", "-c", "pip install --no-cache-dir --disable-pip-version-check aiokafka==0.14.0 aws-msk-iam-sasl-signer-python==1.0.2 && python /app/humo.py"]
          env:
            - { name: KAFKA_BOOTSTRAP_SERVERS, value: "$brokers" }
            - { name: AWS_REGION, value: "$REGION" }
          volumeMounts:
            - { name: app, mountPath: /app, readOnly: true }
          securityContext: { allowPrivilegeEscalation: false, capabilities: { drop: ["ALL"] } }
      volumes:
        - name: app
          configMap: { name: $JOB }
YAML

echo "Job $JOB lanzado; esperando el resultado (instala las librerías, ~1 min)..."
estado=1
if kubectl -n "$NAMESPACE" wait --for=condition=complete "job/$JOB" --timeout=300s >/dev/null 2>&1; then
  estado=0
fi
echo "---- salida del pod ----"
kubectl -n "$NAMESPACE" logs "job/$JOB" --tail=-1 2>&1 | grep -v "^$" | tail -20
echo "------------------------"
if [ "$estado" -eq 0 ]; then
  echo "OK: el bus de eventos funciona (publicar y consumir con SASL/IAM desde un pod)."
else
  echo "FALLO: la prueba de humo no terminó bien." >&2
fi
exit "$estado"
