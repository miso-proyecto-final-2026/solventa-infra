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

# Borde público (módulos nlb, api-gateway y cloudfront): lo crea Terraform, pero un destroy a medias lo deja facturando.
echo "== NLB del borde ($CLUSTER_NAME-nlb)"
nlb=$(aws elbv2 describe-load-balancers \
  --region "$REGION" \
  --query "LoadBalancers[?LoadBalancerName=='$CLUSTER_NAME-nlb'].LoadBalancerArn" --output text 2>/dev/null || true)
if [ -n "$nlb" ]; then
  echo "$nlb" | tr '\t' '\n'
  remaining=1
else
  echo "(ninguno)"
fi

echo "== API Gateway y VPC Link del borde"
apigw=$(aws apigatewayv2 get-apis \
  --region "$REGION" \
  --query "Items[?Name=='$CLUSTER_NAME-api'].ApiId" --output text 2>/dev/null || true)
vpclinks=$(aws apigatewayv2 get-vpc-links \
  --region "$REGION" \
  --query "Items[?Name=='$CLUSTER_NAME-nlb'].VpcLinkId" --output text 2>/dev/null || true)
if [ -n "$apigw$vpclinks" ]; then
  echo "$apigw $vpclinks" | tr ' \t' '\n\n' | sed '/^$/d'
  remaining=1
else
  echo "(ninguno)"
fi

echo "== Distribuciones de CloudFront y WAF del borde (servicios globales: región us-east-1)"
cf=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?starts_with(Comment, '$CLUSTER_NAME:')].Id" --output text 2>/dev/null || true)
# Sin distribuciones la CLI imprime "None" en lugar de una cadena vacía.
[ "$cf" = "None" ] && cf=""
waf=$(aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 \
  --query "WebACLs[?Name=='$CLUSTER_NAME-edge'].Name" --output text 2>/dev/null || true)
if [ -n "$cf$waf" ]; then
  echo "$cf $waf" | tr ' \t' '\n\n' | sed '/^$/d'
  remaining=1
else
  echo "(ninguna)"
fi

echo "== Clúster MSK del bus de eventos ($CLUSTER_NAME-events) y su grupo de logs (facturan por hora)"
msk=$(aws kafka list-clusters-v2 \
  --region "$REGION" --cluster-name-filter "$CLUSTER_NAME-events" \
  --query "ClusterInfoList[].join(' ', [ClusterArn, State])" --output text 2>/dev/null || true)
[ "$msk" = "None" ] && msk=""
msklogs=$(aws logs describe-log-groups \
  --region "$REGION" --log-group-name-prefix "/aws/msk/$CLUSTER_NAME-events" \
  --query "logGroups[].logGroupName" --output text 2>/dev/null || true)
[ "$msklogs" = "None" ] && msklogs=""
if [ -n "$msk$msklogs" ]; then
  [ -n "$msk" ] && echo "$msk"
  [ -n "$msklogs" ] && echo "$msklogs" | tr '\t' '\n'
  remaining=1
else
  echo "(ninguno)"
fi

# Buckets de staging (evidencias KYC y documentos de póliza, HU20). Llevan las etiquetas del proyecto, pero un bucket con
# objetos que sobrevive a un destroy a medias guarda datos: se comprueba por nombre, aparte del barrido por etiquetas.
# El bucket del estado de Terraform (solventa-tfstate-…) no empieza por este prefijo y se conserva a propósito.
echo "== Buckets S3 de staging ($PROJECT-$ENVIRONMENT-…: evidencias KYC y documentos de póliza)"
buckets=$(aws s3api list-buckets \
  --query "Buckets[?starts_with(Name, '$PROJECT-$ENVIRONMENT-')].Name" --output text 2>/dev/null || true)
[ "$buckets" = "None" ] && buckets=""
if [ -n "$buckets" ]; then
  echo "$buckets" | tr '\t' '\n'
  remaining=1
else
  echo "(ninguno)"
fi

if [ "$remaining" -ne 0 ]; then
  echo "FALLO: quedan recursos de staging. Revísalos y elimínalos antes de dar por terminado el teardown." >&2
  exit 1
fi

echo "OK: no quedan recursos de staging."
