#!/bin/sh
# Verifica que el teardown de staging no dejó recursos facturables (SC-002, FR-013).
# Uso: scripts/verificar-teardown.sh [region]
# Sale con código 0 si no queda nada; 1 si quedan recursos; 2 si falta la AWS CLI o las credenciales.
set -eu

REGION="${1:-${AWS_REGION:-us-east-1}}"
CLUSTER_NAME="${CLUSTER_NAME:-solventa-staging}"
PROJECT="${PROJECT:-solventa}"
ENVIRONMENT="${ENVIRONMENT:-staging}"

if ! command -v aws >/dev/null 2>&1; then
  echo "Error: no se encontró la AWS CLI." >&2
  exit 2
fi

if ! aws sts get-caller-identity --region "$REGION" >/dev/null 2>&1; then
  echo "Error: no hay credenciales de AWS válidas." >&2
  exit 2
fi

remaining=0

echo "== Recursos con etiquetas Project=$PROJECT, Environment=$ENVIRONMENT (región $REGION)"
tagged=$(aws resourcegroupstaggingapi get-resources \
  --region "$REGION" \
  --tag-filters "Key=Project,Values=$PROJECT" "Key=Environment,Values=$ENVIRONMENT" \
  --query 'ResourceTagMappingList[].ResourceARN' --output text)
if [ -n "$tagged" ]; then
  echo "$tagged" | tr '\t' '\n'
  remaining=1
else
  echo "(ninguno)"
fi

echo "== Recursos creados por Kubernetes (etiqueta kubernetes.io/cluster/$CLUSTER_NAME)"
by_cluster=$(aws resourcegroupstaggingapi get-resources \
  --region "$REGION" \
  --tag-filters "Key=kubernetes.io/cluster/$CLUSTER_NAME" \
  --query 'ResourceTagMappingList[].ResourceARN' --output text)
if [ -n "$by_cluster" ]; then
  echo "$by_cluster" | tr '\t' '\n'
  remaining=1
else
  echo "(ninguno)"
fi

echo "== Volúmenes EBS con la etiqueta del clúster"
volumes=$(aws ec2 describe-volumes \
  --region "$REGION" \
  --filters "Name=tag-key,Values=kubernetes.io/cluster/$CLUSTER_NAME" \
  --query 'Volumes[].VolumeId' --output text)
if [ -n "$volumes" ]; then
  echo "$volumes" | tr '\t' '\n'
  remaining=1
else
  echo "(ninguno)"
fi

echo "== Interfaces de red (ENI) con la etiqueta del clúster"
enis=$(aws ec2 describe-network-interfaces \
  --region "$REGION" \
  --filters "Name=tag-key,Values=kubernetes.io/cluster/$CLUSTER_NAME" \
  --query 'NetworkInterfaces[].NetworkInterfaceId' --output text)
if [ -n "$enis" ]; then
  echo "$enis" | tr '\t' '\n'
  remaining=1
else
  echo "(ninguna)"
fi

echo "== Balanceadores de carga cuyo nombre sugiere el clúster"
elbs=$(aws elbv2 describe-load-balancers \
  --region "$REGION" \
  --query "LoadBalancers[?contains(LoadBalancerName, 'k8s-')].LoadBalancerArn" --output text 2>/dev/null || true)
if [ -n "$elbs" ]; then
  echo "$elbs" | tr '\t' '\n'
  remaining=1
else
  echo "(ninguno)"
fi

if [ "$remaining" -ne 0 ]; then
  echo "FALLO: quedan recursos de staging. Revísalos y elimínalos antes de dar por terminado el teardown." >&2
  exit 1
fi

echo "OK: no quedan recursos de staging."
