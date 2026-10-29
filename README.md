# solventa-infra

Infraestructura como código (Terraform) de Solventa. Esta rama (`infra/HA04-eks-staging`) construye la
plataforma **staging bajo demanda** en AWS: EKS, PostgreSQL (RDS Multi-AZ), Redis (ElastiCache con réplica),
ECR y Secrets Manager, más todo lo necesario para validarla **sin cuenta de AWS**.

> **Costo.** Con la plataforma encendida cuesta ≈ **USD 0.36 por hora** (≈ USD 8.6 por día). **Destruye
> staging después de cada sesión** (sección [Teardown](#teardown)). La cifra es una estimación a precios de
> lista en `us-east-1` (octubre 2026); contrástala con la
> [AWS Pricing Calculator](https://calculator.aws/) y con Cost Explorer filtrando por la etiqueta `Project`.

## Contenido

1. [Arquitectura](#arquitectura)
2. [Prerrequisitos y permisos](#prerrequisitos-y-permisos)
3. [Pruebas locales](#pruebas-locales)
4. [Bootstrap (una vez por cuenta)](#bootstrap-una-vez-por-cuenta)
5. [Provisión de la plataforma](#provisión-de-la-plataforma)
6. [Acceso al clúster](#acceso-al-clúster)
7. [Publicar la primera imagen](#publicar-la-primera-imagen)
8. [Baseline](#baseline)
9. [Verificación de migraciones](#verificación-de-migraciones)
10. [Acceso privado al backend y pruebas de humo](#acceso-privado-al-backend-y-pruebas-de-humo)
11. [Borde público](#borde-público)
12. [Bus de eventos (MSK)](#bus-de-eventos-msk)
13. [Añadir un microservicio](#añadir-un-microservicio)
14. [CI/CD](#cicd)
15. [Drill HA04](#drill-ha04)
16. [Teardown](#teardown)
17. [Errores frecuentes](#errores-frecuentes)
18. [Eliminar todo de la cuenta (limpieza total)](#eliminar-todo-de-la-cuenta-limpieza-total)
19. [Notas operativas](#notas-operativas)

## Arquitectura

Tres raíces de Terraform con ciclos de vida distintos:

| Raíz | Qué contiene | Ciclo de vida |
|---|---|---|
| `bootstrap/` | Bucket S3 de estado (bloqueo nativo), proveedor OIDC de GitHub y roles de CI | Una vez; **sobrevive al teardown**, no cuesta |
| `environments/staging/platform/` | VPC (2 AZ), EKS `solventa-staging` (3 × `t3.medium`), ECR, RDS PostgreSQL 16 Multi-AZ, ElastiCache Redis con failover, secretos | Bajo demanda |
| `environments/staging/baseline/` | Dentro del clúster: metrics-server, External Secrets, Prometheus y Prometheus Adapter (HPA por concurrencia), Job `db-access`, y por servicio Deployment, Service, HPA, PDB y migración | Bajo demanda |

- La lista de servicios vive **una sola vez** en `environments/staging/services.yaml` (contrato C1).
- `modules/baseline` es la composición compartida: la usan `environments/staging/baseline` (AWS) y
  `local/kind` (clúster local) sin cambios.
- Credenciales: RDS gestiona la contraseña maestra; las de servicio y caché son aleatorias y viven en
  Secrets Manager. Terraform solo crea referencias (`ExternalSecret`); ningún valor sensible sale en
  salidas, planes ni logs.
- Todos los recursos llevan las etiquetas `Project`, `Environment`, `Repository`, `ManagedBy` y `Stage`.

Estructura:

```text
bootstrap/  environments/staging/{platform,baseline,services.yaml}  modules/  local/{kind,emulator}
tests/mutations/  scripts/  .github/workflows/{ci,platform-ops,commitlint,release}.yml
```

## Prerrequisitos y permisos

| Uso | Herramientas (todas gratuitas) |
|---|---|
| Local | Terraform ≥ 1.10 (CI usa 1.15.x), tflint, checkov (`pip`), gitleaks, Docker o Podman, kind, kubectl. En Windows, scripts `.sh` con Git Bash o WSL |
| Remoto | Lo anterior + AWS CLI v2 y un principal IAM con permisos para ejecutar el bootstrap la primera vez (crear S3, IAM y OIDC). Después se usa el rol de apply o un administrador de la cuenta |

Para las pruebas locales **no debe haber credenciales AWS configuradas** (`AWS_PROFILE` sin definir).

### Permisos del principal IAM (remoto)

El principal que ejecuta bootstrap y plataforma debe tener **`AdministratorAccess`** y usarse solo en una
**cuenta de pruebas**. Motivo: crear roles IAM equivale a ser administrador, las políticas acotadas chocan con
el límite de 10 políticas gestionadas por usuario y siempre acaban faltando permisos (p. ej. `ssm:GetParameter`).

1. Consola de AWS → IAM → Users → **Create user** → *Attach policies directly* → `AdministratorAccess`.
2. En el usuario creado, pestaña *Security credentials* → *Create access key* (uso: CLI).
3. En tu terminal: `aws configure` (región `us-east-1`) y comprueba con `aws sts get-caller-identity`.

Antes, limpia variables antiguas que pisan la configuración:
`unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE`.
En Windows usa **Git Bash** (obligatorio para los `.sh`; no PowerShell ni CMD).

### Cuota de vCPU en cuentas nuevas

Una cuenta nueva puede tener la cuota EC2 `L-1216C47A` (*Running On-Demand Standard instances*, en vCPU) en 0 y el
node group falla con `AsgInstanceLaunchFailures ... quota for maximum Fleet Requests`. **Compruébala antes del apply**:

```sh
aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A \
  --region us-east-1 --query Quota.Value
# Si es < 16, solicita el aumento (3 × t3.medium necesitan 6 vCPU; pide ≥ 16 para tener margen)
aws service-quotas request-service-quota-increase --service-code ec2 --quota-code L-1216C47A \
  --region us-east-1 --desired-value 16
```

Comprueba también que la cuenta tiene un método de pago válido; sin él AWS puede rechazar o retrasar el aumento.

### Marcadores en los comandos

Los valores entre `< >` (`<state_bucket>`, `<SHA>`, `<ACCOUNT_ID>`) son **marcadores**: se reemplazan **sin** los
`< >`. Pasar el literal produce `InvalidBucketName`. El nombre del bucket se obtiene con
`terraform -chdir=bootstrap output state_bucket`.

## Pruebas locales

Todo corre sin cuenta de AWS y en ≤ 20 minutos (SC-003). Desde la raíz del repositorio:

```sh
# 1. Formato, validación y lint
terraform fmt -check -recursive
for d in bootstrap environments/staging/platform environments/staging/baseline local/kind local/emulator; do
  terraform -chdir=$d init -backend=false && terraform -chdir=$d validate
done
tflint --init && tflint --recursive

# 2. Escaneo de configuración y de secretos
checkov --config-file .checkov.yaml
gitleaks detect --no-banner

# 3. Pruebas con proveedores simulados (mock_provider)
for d in modules/* bootstrap environments/staging/platform environments/staging/baseline; do
  [ -d $d/tests ] && terraform -chdir=$d init -backend=false && terraform -chdir=$d test
done

# 4. Comprobación de mutaciones: cada parche rompe una regla y la prueba DEBE fallar (SC-006)
scripts/mutation-check.sh
```

**Emulador de la API de AWS (Moto).** Aplica bootstrap, red, ECR y secretos contra un servidor local:

```sh
docker run -d --name moto -p 5000:5000 motoserver/moto:5.1.4
terraform -chdir=local/emulator init && terraform -chdir=local/emulator apply -auto-approve
docker rm -f moto
```

Si una versión de Moto no cubre algún recurso, desactívalo con `-var enable_network=false` o
`-var enable_ci_identities=false` (documentado en `local/emulator/variables.tf`).

**Kubernetes local (kind).** Ejecuta el mismo baseline con PostgreSQL 16 y Redis 7 dentro del clúster:

```sh
kind create cluster --name solventa --config local/kind/kind-config.yaml   # 3 workers, 2 zonas simuladas
# Requiere un backend cuya imagen incluya Alembic (alembic.ini y migrations/); si tu rama no los tiene aún,
# construye desde la rama con las migraciones (feature/HU12-persistencia-alembic o test/HU12-contrato-modulo-ci).
docker build -t solventa-backend:local ../solventa-backend
kind load docker-image solventa-backend:local --name solventa
terraform -chdir=local/kind init && terraform -chdir=local/kind apply -auto-approve
kubectl -n staging port-forward svc/solventa-backend 8000:80 &
curl -s localhost:8000/health
curl -s -XPOST localhost:8000/v1/cotizaciones -H 'Content-Type: application/json' \
  -d '{"cliente_id":"local-1","producto":"microseguro_vida","datos":{"edad":35,"suma_asegurada":50000000}}'
kind delete cluster --name solventa
```

Esperado: los Jobs `db-access` y `solventa-backend-migrate-<hash>` terminan antes de que exista el
Deployment, hay 2 réplicas repartidas en ambas zonas, el HPA muestra métricas y repetir la petición con el
mismo `cliente_id` devuelve `metadata.hit_cache: true`.

**Aislamiento de esquemas (ensayo local).** Construye la imagen mínima de `ms-prueba` (`docker build -t ms-prueba:local -f local/kind/Dockerfile.ms-prueba local/kind` y `kind load docker-image ms-prueba:local --name solventa`) y aplica `-var services_file=services.extra.yaml` (añade `ms-prueba`
con el esquema `identidad`) y usa `scripts/sql/verificar-aislamiento.sql` como administrador:
`psql -v owner_role=solventa_backend -v other_role=ms_prueba -v schema=cotizacion -v table=cotizaciones -f scripts/sql/verificar-aislamiento.sql`.

### Qué se verifica dónde

| Capa | Mocks (`terraform test`) | Moto | kind | Solo en AWS |
|---|---|---|---|---|
| Reglas FR-030 (RDS privado/cifrado/Multi-AZ, caché cifrada, etiquetas, roles) | ✔ | — | — | — |
| Roles de CI, bucket de estado, ECR, secretos, VPC | ✔ | ✔ (API simulada) | — | Comportamiento real de IAM |
| `db-access`, migraciones, Deployment, HPA, PDB, ESO (store `kubernetes`) | ✔ (plan) | — | ✔ (ejecución real) | ESO con Secrets Manager y Pod Identity |
| EKS, RDS Multi-AZ, ElastiCache, NAT, conectividad privada | ✔ (plan) | ✗ (solo API) | — | ✔ |
| Failover, pérdida de AZ, tiempos y costos | — | — | — | ✔ (drill y Cost Explorer) |

Lo que **no** se puede probar localmente: TLS real hacia RDS/ElastiCache, `rds.force_ssl`, Pod Identity,
autenticación EKS y los tiempos de provisión.

## Bootstrap (una vez por cuenta)

```sh
terraform -chdir=bootstrap init
terraform -chdir=bootstrap apply          # crea bucket de estado, OIDC y roles de CI
terraform -chdir=bootstrap output
```

Si la cuenta ya tiene el proveedor OIDC de GitHub: `-var create_github_oidc_provider=false` (si no, el apply
falla porque el proveedor ya existe; solo puede haber uno por cuenta).

**Qué es el proveedor OIDC de GitHub.** Es una relación de confianza entre la cuenta de AWS y GitHub Actions:
los workflows obtienen credenciales temporales asumiendo un rol de IAM, sin guardar claves de larga duración.
Cada rol solo confía en el repositorio indicado. Por eso `deploy_repository` en
`environments/staging/services.yaml` debe apuntar al **repositorio real** (`owner/repo`) del servicio: si no
coincide, el rol de despliegue rechaza el `AssumeRoleWithWebIdentity` del CI.

Migra el estado al bucket recién creado: descomenta el bloque `backend "s3"` de `bootstrap/versions.tf` y ejecuta
`terraform -chdir=bootstrap init -migrate-state -backend-config="bucket=<state_bucket>" -backend-config="region=us-east-1"`.

Copia `environments/staging/backend.hcl.example` a `environments/staging/backend.hcl` y completa el bucket
(sin `< >`; ver [Marcadores](#marcadores-en-los-comandos)).

## Provisión de la plataforma

```sh
terraform -chdir=environments/staging/platform init -backend-config=../backend.hcl
terraform -chdir=environments/staging/platform apply -var-file=staging.tfvars
terraform -chdir=environments/staging/platform output     # no debe mostrar ningún valor sensible
```

Tarda ≈ 25–30 min (RDS Multi-AZ y EKS en paralelo). Comprueba antes la [cuota de vCPU](#cuota-de-vcpu-en-cuentas-nuevas).
El aviso *"You didn't use the -out option"* del apply es normal: no indica ningún problema.

En `staging.tfvars`:

- `api_allowed_cidrs`: restríngelo a tu IP pública en `/32` (p. ej. `["<TU_IP>/32"]`, sin `< >`).
- `cluster_admin_principal_arns`: **debe incluir el ARN de quien opera**; si no, `kubectl` responde
  `Unauthorized`. Si usas un rol SSO, pon el ARN del **rol** (`arn:aws:iam::<ACCOUNT_ID>:role/...`), no el de la
  sesión (`assumed-role/...`).

El rol de apply de CI siempre es administrador del clúster; añade a las personas que operen con
`cluster_admin_principal_arns`.

> **Versión de Kubernetes.** `kubernetes_version = "1.35"` con `support_type = STANDARD`. Al salir de soporte
> estándar, EKS cobra seis veces el plano de control (soporte extendido): actualiza la versión antes
> (`aws eks describe-cluster-versions`) y revisa los add-ons.

## Acceso al clúster

```sh
aws eks update-kubeconfig --name solventa-staging --region us-east-1
kubectl get nodes -o wide        # 3 nodos en 2 AZ
```

Solo entran los principales listados como access entries (administradores, rol de plan en solo lectura y
roles de despliegue con permisos únicamente en el namespace `staging`).

## Publicar la primera imagen

```sh
REGISTRY=$(terraform -chdir=environments/staging/platform output -raw registry_url)
SHA=$(git -C ../solventa-backend rev-parse HEAD)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$REGISTRY"
docker build -t "$REGISTRY/solventa-backend:$SHA" ../solventa-backend
docker push "$REGISTRY/solventa-backend:$SHA"
```

Los tags son inmutables: usa el SHA del commit. También puede publicarla el `deploy-staging` del backend
(publica y omite el rollout hasta que exista el baseline).

## Baseline

```sh
aws eks update-kubeconfig --name solventa-staging --region us-east-1
terraform -chdir=environments/staging/baseline init -backend-config=../backend.hcl
terraform -chdir=environments/staging/baseline apply -var-file=staging.tfvars \
  -var "state_bucket=<state_bucket>" -var 'image_tags={"solventa-backend":"<SHA>"}'
```

- Si la imagen no está en ECR, falla antes de tocar cargas: `Image solventa-backend:<tag> not found. Push it first`.
- **Importante:** `image_tag` debe coincidir con el SHA que está corriendo antes de un apply del baseline que
  lo cambie. Si no, se recrea el Job de migración con una imagen anterior y Alembic puede fallar con
  `Can't locate revision`.
- Orden dentro del apply: secreto → Job `db-access` → Job de migración → Deployment.

## Verificación de migraciones

```sh
kubectl -n solventa-system get jobs                     # db-access Complete
kubectl -n staging get jobs                             # solventa-backend-migrate-<hash> Complete
kubectl -n staging logs job/<job-de-migración>
kubectl -n staging get pods -o wide                     # ≥ 2 réplicas en nodos de ambas AZ
kubectl -n staging get pods -l app.kubernetes.io/name=<servicio>   --field-selector=status.phase=Succeeded                # vacío
```

Los pods de migración llevan `app.kubernetes.io/name = <servicio>-migrate` (y `component = migration`) para quedar
fuera del selector del Deployment, que también usan el HPA y el PDB: un pod `Succeeded` dentro de él contaría con
métrica 0 y, sin request de CPU, dejaría la métrica de CPU del HPA en `<unknown>` (HA03, `RULE migration-labels`).

## Acceso privado al backend y pruebas de humo

El backend es `ClusterIP`: no hay balanceador público. Accede por túnel:

```sh
kubectl -n staging port-forward svc/solventa-backend 8000:80 &
curl -s localhost:8000/health                                                       # 200
curl -s -XPOST localhost:8000/v1/cotizaciones -H 'Content-Type: application/json' \
  -d '{"cliente_id":"smoke-1","producto":"microseguro_vida","datos":{"edad":35,"suma_asegurada":50000000}}'   # 201
```

- **Persistencia:** desde un pod efímero en `solventa-system` con `psql`, comprueba la fila en `cotizacion.cotizaciones`.
- **Caché:** repetir la petición con el mismo `cliente_id` devuelve `metadata.hit_cache: true`.

**MS Suscripción (HU15)** sí se publica por el borde (`/v1/suscripciones`, NodePort 30082): la app móvil lo llama con el token del cliente. Depende de tres vecinos por REST interno (Identidad, Cotización y Perfilamiento, con sus claves de servicio en Secrets Manager) y **publica en el bus**, así que necesita `enable_events = true`: sin brokers no arranca fuera de modo desarrollo. Al agregarlo, `bootstrap` crea su rol de despliegue y su repositorio de imágenes: actualice la variable `AWS_DEPLOY_ROLE_ARNS` del repo del backend con la salida `service_deploy_role_arns` antes del primer `cicd/deploy-staging`.

**MS Perfilamiento (HU23)** tampoco se publica por el borde: devuelve datos financieros del cliente y solo lo consumen otros servicios, así que su entrada en `services.yaml` no declara `edge`. Se prueba por túnel con su clave de servicio (el valor lo crea `platform` en `solventa/staging/perfilamiento-api-key`):

```sh
KEY=$(aws secretsmanager get-secret-value --secret-id solventa/staging/perfilamiento-api-key --query SecretString --output text | python3 -c 'import sys,json;print(json.load(sys.stdin)["value"])')
kubectl -n staging port-forward svc/solventa-perfilamiento 8002:80 &
curl -s -XPOST -H "X-Service-Key: $KEY" localhost:8002/v1/perfilamiento/smoke-1/enriquecer      # 201
curl -s -H "X-Service-Key: $KEY" localhost:8002/v1/perfilamiento/smoke-1/linaje                 # fuentes, TTL y fechas
```

En Postman basta apuntar `perfilamiento_url` a `http://localhost:8002` mientras dure el túnel.

**MS Siniestros (HU27)** sí se publica por el borde (`/v1/siniestros`, NodePort 30083, `high_volume`): el proveedor de eventos es externo. Recibe `KAFKA_BOOTSTRAP_SERVERS` y `AWS_DEFAULT_REGION` de `baseline` (el cliente de eventos firma el token SASL/IAM con la región), tiene permisos solo sobre `solventa.siniestros.eventos` y el grupo `solventa-siniestros.recepcion`, y su llave sale de `solventa/staging/siniestros-api-key` (valor aleatorio sin nombre: el servicio la asocia a la fuente `proveedor-simulado`). Prueba por el borde, con staging encendido y el servicio desplegado:

```sh
KEY=$(aws secretsmanager get-secret-value --secret-id solventa/staging/siniestros-api-key --query SecretString --output text | python3 -c 'import sys,json;print(json.load(sys.stdin)["value"])')
URL=$(terraform -chdir=environments/staging/platform output -raw public_url)
curl -s -XPOST "$URL/v1/siniestros/eventos" -H "X-Service-Key: $KEY" -H 'Content-Type: application/json' \
  -d '{"evento_id":"humo-1","tipo":"sismo","fuente":"proveedor-simulado","ocurrido_en":"2026-10-23T14:05:00Z","datos":{"magnitud":6.4}}'   # 202
curl -s -H "X-Service-Key: $KEY" "$URL/v1/siniestros/eventos/resumen"                                                                     # recibidos, publicados, procesados
```

**MS Pagos (HU18, HU19)** publica en el borde **solo** la gestión de cobros fallidos de la consola web (`/v1/pagos/cobros-fallidos`, NodePort 30084, con el JWT del asesor u operador: `ASESOR_JWT_SECRETO`, el mismo de Identidad). Cobrar, tokenizar y consultar transacciones manejan tokens de pago y siguen internos (SAQ-A): se declaran en `internal_path_prefixes` y la regla V15 impide publicarlos. Además publica el aviso de gracia vencida en `solventa.notificaciones` (HU19). Esquema propio `pagos` (salió de los reservados). Consume `solventa.suscripcion.comandos` en el grupo `solventa-pagos.cobros` y publica el resultado en `solventa.pagos.resultados`; MS Suscripción consume ese topic en `solventa-suscripcion.pagos`. La pasarela es el simulador (`PASARELA_PROVEEDOR=simulador`, modo por defecto `APROBAR`; el prefijo del token elige otro modo, ver `services/pagos/README.md` del backend). `PERIODO_GRACIA_DIAS=3` es **provisional**. Necesita `enable_events = true`. Al agregarlo, `bootstrap` crea su rol de despliegue y su repositorio de imágenes: actualice `AWS_DEPLOY_ROLE_ARNS` en el backend antes del primer `cicd/deploy-staging`. Se prueba por túnel con su clave (la crea `platform` en `solventa/staging/pagos-api-key`):

```sh
KEY=$(aws secretsmanager get-secret-value --secret-id solventa/staging/pagos-api-key --query SecretString --output text | python3 -c 'import sys,json;print(json.load(sys.stdin)["value"])')
kubectl -n staging port-forward svc/solventa-pagos 8005:80 &
curl -s -XPOST localhost:8005/v1/pagos/cobros -H "X-Service-Key: $KEY" -H 'Content-Type: application/json'   -d '{"suscripcion_id":"humo-1","cliente_id":"humo","metodo_pago":"tok_sim_humo","monto":"1000.00"}'      # 201 APROBADA
curl -s -H "X-Service-Key: $KEY" localhost:8005/v1/pagos/transacciones/<id>                             # estado
```

En Postman: `pagos_url` = `http://localhost:8005` y la clave como valor actual de `pagos_key` mientras dure el túnel.

## Borde público

Implementa la ruta de entrada del documento de arquitectura: **cliente → CloudFront (TLS) + WAF → API Gateway → NLB interno → NodePort de cada servicio**. Se crea en la etapa `platform` (variable `enable_edge`, activa por defecto) y lo crea todo Terraform: el clúster no crea balanceadores, así que el destroy no deja ninguno huérfano.

| Módulo | Qué crea |
|---|---|
| `modules/cloudfront` | Distribución de CloudFront (HTTPS, sin caché de la API, sin Host) y el WAF vinculado |
| `modules/api-gateway` | HTTP API, VPC Link, una integración por servicio y rutas por prefijo (`/v1/cotizaciones`, `/v1/clientes`, `/v1/suscripciones`, `/v1/siniestros`, `/v1/pagos/cobros-fallidos`) con throttling |
| `modules/nlb` | NLB interno multi-AZ (capa 4), un listener y un grupo de destinos por servicio, y los nodos registrados desde su grupo de autoescalado |
| `modules/service-workload` | Un Service `NodePort` fijo (`<servicio>-edge`) por servicio expuesto |

Un servicio se expone declarando `edge` en `environments/staging/services.yaml` (contrato C1, regla V9):

```yaml
edge:
  node_port: 30080                  # 30000-32767, único; el listener del NLB usa el mismo puerto
  path_prefixes: [/v1/cotizaciones] # absolutos, sin barra final, únicos entre servicios
```

Cada prefijo crea las rutas `ANY <prefijo>` y `ANY <prefijo>/{proxy+}`: publica ese segmento y todo lo que cuelga de él,
no los segmentos hermanos (`/v1/pagos/cobros-fallidos` no publica `/v1/pagos/cobros`). Las rutas que nunca deben salir al
borde se declaran en el servicio con `internal_path_prefixes`; la regla V15 rechaza cualquier `path_prefixes` (de
cualquier servicio) igual a una de ellas, debajo de ella o más corto que la cubra (por ejemplo `/v1/pagos`).

**Servicios de alto volumen (`high_volume`).** Un proveedor externo de eventos (HU27, `solventa-siniestros`) envía ráfagas legítimas: la meta EC-E2.1 son ≈ 1.670 eventos/s, y con los límites generales (1000 solicitudes por IP en 5 min en el WAF, 200 rps / 400 de ráfaga en el API Gateway) un solo proveedor recibiría 429 a los pocos minutos. Con `edge.high_volume: true` sus rutas:

- quedan **fuera** de la regla global del WAF y tienen la suya (`rate-limit-high-volume`, `edge_high_volume_rate_limit_per_5min`, 600.000 por IP en 5 min ≈ 2.000/s);
- tienen throttling propio en el API Gateway (`edge_high_volume_throttling_rate_limit` 2.000 rps y `..._burst_limit` 4.000), por ruta.

El resto de rutas conserva los límites bajos. El límite alto no es infinito: sigue habiendo tope por IP, SQLi/XSS y geo blocking. **Si el proveedor real está fuera de CO y US, el WAF lo bloquea** (`edge_allowed_countries`).

Reglas del WAF (sección 5.3 de la documentación técnica): SQL injection (conjunto administrado de AWS), XSS, rate limiting global de 1000 solicitudes por IP en 5 minutos (429), geo blocking fuera de CO y US (`edge_allowed_countries`) y cuerpo máximo de 256 KB (413).

**Exención de la verificación de identidad.** La subida de HU02 (`POST /v1/clientes/{id}/verificaciones`) es multipart con tres imágenes: supera 256 KB y es binaria. Esa única ruta queda exenta del límite de cuerpo y de la inspección de contenido (`exempt_body_path_regex`); el servicio ya rechaza las imágenes que superan su máximo.

Salidas de `platform`: `public_url` (la URL que usan la app y los compañeros), `api_gateway_endpoint` y `nlb_dns_name`.

Limitaciones conocidas:
- **El API Gateway tiene endpoint público propio** (`api_gateway_endpoint`) y se puede llamar sin pasar por CloudFront ni el WAF. Cerrarlo requiere un dominio propio o un autorizador; los clientes deben usar `public_url`.
- **No se valida OAuth2/OIDC en el borde todavía.** MS Identidad emite un token opaco propio, no un JWT; cada servicio lo valida. Falta el rate limiting por socio (`cuota_rps`).
- **CloudFront tarda en crearse y destruirse** (varios minutos cada vez). El WAF de alcance CLOUDFRONT solo existe en `us-east-1`.
- Un destroy a medias deja el borde facturando: `scripts/verificar-teardown.sh` lo comprueba (NLB, API Gateway, VPC Link, distribución y WAF).

## Bus de eventos (MSK)

Kafka (Amazon MSK) es el bus de las comunicaciones asíncronas del ADR-0002: saga de suscripción, pagos, notificaciones y pago
paramétrico (HS2). Lo crea `platform`; `baseline` crea los topics.

- **Qué es:** un clúster privado de 2 brokers `kafka.t3.small` (uno por zona), TLS en tránsito y en reposo, sin acceso público.
  Solo los nodos de EKS llegan a él, por el puerto 9098 (SASL/IAM). Los topics no se crean solos
  (`auto.create.topics.enable=false`), y la replicación es 2 con `min.insync.replicas=1`, para seguir con un broker caído.
- **Costo y tiempo:** factura **por broker-hora**, aparte del resto de staging, y tarda ~25 min en crearse. Si la sesión no usa
  eventos, ponga `enable_events = false` en `staging.tfvars`: no crea el clúster ni el Job de topics.
- **Topics:** se declaran en `topics:` de `environments/staging/services.yaml` (contrato de la documentación técnica §4.2:
  nombre, clave de partición, particiones, retención y cola de mensajes fallidos `<topic>.dlq`). Un Job de `baseline`
  (`modules/kafka-topics`) los crea desde dentro de la VPC y es idempotente.
- **Permisos mínimos:** cada servicio declara qué `eventos: { produce: [...], consume: [...] }` usa y recibe un rol de Pod
  Identity solo con esos topics. Quien consume puede además escribir en `<topic>.dlq` de lo que consume. Los grupos de consumo
  deben empezar por el nombre del servicio (`solventa-suscripcion.<algo>`). Un servicio no puede leer los topics de otro.
- **Conexión:** los servicios con `eventos` reciben `KAFKA_BOOTSTRAP_SERVERS` por su ConfigMap (no es un secreto: solo funciona
  con una identidad autorizada). No se define a mano. La autenticación es SASL/OAUTHBEARER firmada con IAM; el cliente de
  referencia está en `docs/plantillas/eventos/` del backend.
- **Prueba de humo** (con staging encendido y `baseline` aplicado): `scripts/prueba-humo-kafka.sh` lanza un Job con la
  identidad `kafka-humo` que publica un evento en `solventa.humo` y lo consume de vuelta. Sale con 0 si llegó.
- **Teardown:** `scripts/verificar-teardown.sh` revisa también el clúster MSK y su grupo de logs. Los logs de los brokers van a
  CloudWatch (`/aws/msk/<nombre>`, 14 días) y sirven de evidencia de auditoría.

## Autoescalado por solicitudes concurrentes (HA03)

Con caché, la CPU de Cotización no sigue al volumen (hallazgo de HA02) y el HPA por CPU no escala. Por eso
`solventa-backend` escala por **solicitudes en curso por pod** (ADR-0015 de `solventa-backend`):

```text
pod (/metrics, gauge http_requests_in_flight) --scrape 15 s--> Prometheus --avg_over_time 30 s--> Prometheus Adapter
  --custom.metrics.k8s.io--> HPA (Pods: AverageValue; CPU de respaldo)
```

- `modules/cluster-addons` instala, en el namespace `monitoring`, un **Prometheus mínimo** (solo el trabajo
  `kubernetes-pods`; sin Alertmanager, exportadores ni volumen persistente; retención de 2 h) y **Prometheus Adapter**
  con una sola regla. Lo usan igual AWS y `local/kind`.
- Un servicio se suma declarando en `services.yaml`:

  ```yaml
  metrics_path: /metrics             # anota el pod con prometheus.io/scrape, port y path
  autoscaling:
    cpu_target_percent: 70           # sigue como respaldo: el HPA toma la recomendación más alta
    concurrent_requests_target: 16   # solicitudes en curso promedio por pod (requiere metrics_path, V14)
    scale_up: { pods: 4, percent: 100, period_seconds: 15, stabilization_window_seconds: 0 }
  ```

  `scale_up` es opcional; por defecto se queda la política de siempre (2 pods cada 60 s tras 30 s de estabilización).
  Hoy solo `solventa-backend` declara la métrica y abre la subida; la bajada es igual para todos (1 pod cada 60 s tras 300 s).
- El objetivo de 16 sale de la ley de Little calibrada con el humo de la sesión de HA03 del 2026-10-25 (ADR-0015 de
  `solventa-backend`, Supuesto 3); partió de una estimación de 3.
- **`/metrics` no se publica.** El API Gateway solo enruta los prefijos de `edge` (no hay ruta `$default` ni
  `/{proxy+}`), y la regla V13 impide que `metrics_path` o `health_path` queden bajo un prefijo público. Prometheus lo
  recoge directo de la IP del pod. **Dentro de la VPC sí es legible, y se acepta:** comparte puerto con la app, así
  que llega por el NodePort del NLB interno y por el Service `ClusterIP` (no hay NetworkPolicy: el VPC CNI no tiene
  activado el agente de políticas). Es un único gauge, sin etiquetas ni datos de clientes. Mejora futura: servirlo en
  un puerto aparte que ningún Service ni NodePort exponga y, con NetworkPolicy, abrirlo solo a `monitoring`
  (ADR-0015 de `solventa-backend`).
- Si Prometheus o el adaptador caen, el HPA marca la métrica como no disponible y sigue escalando por CPU.

Comprobar la cadena: `kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/staging/pods/*/http_requests_in_flight"`
y `kubectl -n staging describe hpa solventa-backend` (dos métricas).

## Añadir un microservicio

1. Añade una entrada a `environments/staging/services.yaml` (formato en `specs/001-aws-eks-staging-infra/contracts/service-entry.md`).
   Las validaciones V1–V15 fallan en el plan con mensajes claros.
2. `terraform -chdir=bootstrap apply` — crea el rol de despliegue del servicio (solo `+`).
3. `terraform -chdir=environments/staging/platform apply -var-file=staging.tfvars` — repositorio ECR, secreto de BD y access entry (solo `+`).
4. Publica la imagen del nuevo servicio.
5. `terraform -chdir=environments/staging/baseline apply ...` — todos los objetos del servicio.

Notas:

- **Secretos compartidos entre servicios** (p. ej. la clave con la que Cotización consulta a Identidad): declara en cada servicio
  `secret_env_vars: { VARIABLE: solventa/staging/<nombre> }`. `platform` crea el secreto una sola vez con un valor aleatorio
  (no vive en git ni en variables) y el baseline lo entrega como variable de entorno por ExternalSecret. Los dos servicios
  que apuntan al mismo nombre reciben el mismo valor. Solo aplica a AWS; `local/kind` no lo provee.
- **Clave de auditor (HU14/HU11):** `solventa-backend` recibe `AUDITOR_API_KEYS` desde `solventa/staging/auditor-api-key`
  (valor aleatorio creado por `platform`). Quien audite la envía en la cabecera `X-Service-Key` de
  `GET /v1/cotizaciones/{id}/desglose` y `/consultas-externas`. Para leerla:
  `aws secretsmanager get-secret-value --secret-id solventa/staging/auditor-api-key --query SecretString --output text`
  (la propiedad es `value`). Es provisional hasta los roles internos (F26).
- **Evidencias KYC (HU02):** `platform` crea el bucket `solventa-<env>-kyc-evidencias-<cuenta>` (cifrado, sin acceso público,
  solo TLS, versionado y con retención de 90 días) y autoriza por Pod Identity únicamente a la cuenta de servicio
  `solventa-identidad` con `s3:PutObject` bajo `kyc/`. El baseline entrega el nombre y la región al servicio
  (`KYC_EVIDENCIAS_BUCKET`, `AWS_DEFAULT_REGION`). La lectura para revisión manual no está habilitada: requeriría otro rol.
  En staging el bucket se crea con `force_destroy` porque solo guarda evidencias sintéticas y se destruye tras cada sesión.
- **Eventos (HS2):** si el servicio publica o consume, declara `eventos: { produce: [...], consume: [...] }` con topics ya declarados en `topics:`; `platform` crea su rol de Pod Identity y `baseline` le entrega `KAFKA_BOOTSTRAP_SERVERS`. Ver [Bus de eventos (MSK)](#bus-de-eventos-msk).
- Un servicio nuevo necesita su imagen en ECR antes del baseline (paso 4); el baseline falla antes de tocar cargas si no está.
- El plan del baseline muestra solo `+`, **salvo** los objetos de `db-access` (Job y ConfigMap de SQL reemplazados, ExternalSecret de contraseñas actualizado) porque cambia su hash.
  Es esperado: es un Job de una sola ejecución (junto con su ConfigMap de SQL y el ExternalSecret de contraseñas, que se actualizan) y reemplazarlo no causa interrupciones.
- **Mover un esquema** (quitarlo de un servicio y añadirlo a otro): el dueño del esquema y de todos sus objetos
  cambia, las filas se conservan y el servicio anterior pierde el acceso.
- **Quitar un servicio:** se eliminan sus objetos, repositorio y secretos; su rol de BD se retira y sus
  esquemas pasan a *reservados* **con los datos intactos**. Un esquema solo se elimina si lo listas en
  `drop_schemas` y no tiene dueño.
- Cada servicio debe poder migrar con su propio usuario; al extraer un esquema, el equipo del backend debe
  retirar las migraciones correspondientes (de lo contrario su migración falla con `permission denied`, por diseño).

## CI/CD

| Evento | Qué ocurre |
|---|---|
| PR o push a `main` | `validate` (fmt, init, validate, tflint), `test` (terraform test + mutaciones), `scan` (checkov, gitleaks), `emulator` (Moto) y `plan` de solo lectura |
| Merge a `main` | Los mismos controles y un plan. **Nunca** aplica |
| `workflow_dispatch` de `platform-ops` | `apply` o `destroy` con aprobación del environment `staging` |
| Merge en `solventa-backend` | `deploy-staging`: guardia de clúster, build y push, guardia de baseline, migración y rollout |

Variables y environments de GitHub (contrato C4):

| Repositorio | Variable | Valor |
|---|---|---|
| `solventa-infra` | `AWS_PLAN_ROLE_ARN` | salida `infra_plan_role_arn` (reemplaza a `AWS_ROLE_ARN`) |
| `solventa-infra` | `AWS_APPLY_ROLE_ARN` | salida `infra_apply_role_arn` |
| `solventa-infra` | `TF_STATE_BUCKET` | salida `state_bucket` |
| `solventa-backend` | `AWS_ROLE_ARN` | `service_deploy_role_arns["solventa-backend"]` |
| `solventa-backend` | `AWS_DEPLOY_ROLE_ARNS` | salida `service_deploy_role_arns` del bootstrap, completa (incluye `solventa-siniestros` y `solventa-pagos`; el despliegue por comentario `cicd/deploy-staging` falla si falta el rol del servicio) |
| `solventa-backend` | `AWS_ROLE_ARN_PERFILAMIENTO` | `service_deploy_role_arns["solventa-perfilamiento"]` (HU23; habilita el job `deploy-staging-perfilamiento`) |

- Ambos repositorios necesitan un environment llamado `staging` (la confianza OIDC de apply y deploy depende de él).
- En `solventa-infra`, el environment `staging` **debe** tener revisores requeridos.
- Tras un rollout de CI, un plan no propone cambiar la imagen (`ignore_changes`, SC-008).
- Prueba de RBAC con el rol de despliegue: `kubectl auth can-i patch deployments -n staging` → `yes`;
  `... -n kube-system` → `no`; `kubectl auth can-i create secrets -n staging` → `no`.

## Drill HA04

Con tráfico constante de cotizaciones y la plataforma encendida:

```sh
kubectl -n staging port-forward svc/solventa-backend 8000:80 &
scripts/drill-trafico.sh http://localhost:8000 900 1     # deja un log con hora, código y cliente_id
```

| Falla | Comando | Objetivo (SC-007) |
|---|---|---|
| Failover de RDS | `aws rds reboot-db-instance --db-instance-identifier solventa-staging-postgres --force-failover` | recuperación ≤ 5 min |
| Failover de caché | `aws elasticache test-failover --replication-group-id solventa-staging-cache --node-group-id 0001` | ≤ 1 min |
| Pérdida de una AZ | `kubectl cordon` y `kubectl drain --ignore-daemonsets --delete-emptydir-data` de los nodos de una AZ | reprogramación ≤ 2 min |

**Dispersión entre zonas.** Las réplicas de cada servicio se reparten por zona con `DoNotSchedule` (máximo una de
diferencia) y `node_taints_policy = Honor`. Con `ScheduleAnyway` el scheduler a veces las dejaba todas en una AZ. Los
nodos acordonados o caídos tienen un taint `NoSchedule` y no cuentan como zona, así que durante el drill las réplicas de
la AZ perdida se reprograman en la superviviente. Si una zona sana se queda sin capacidad, las réplicas nuevas quedan
`Pending` en lugar de amontonarse en la otra: revisa `kubectl -n staging get pods -o wide` y los eventos del scheduler.
Por nodo la dispersión sigue siendo preferencia (`ScheduleAnyway`) para no bloquear el escalado.

Cómo registrar resultados:

1. Anota la hora de inicio de cada falla y la del primer `201` posterior en el log: la diferencia es el tiempo de recuperación.
2. Cuenta las cotizaciones confirmadas (`201`) y compáralas con las filas de `cotizacion.cotizaciones` cuyo
   `cliente_id` empieza por el identificador del run (el script imprime la consulta). La diferencia es la pérdida; el objetivo es **0**.
3. Guarda tiempos y pérdida en el log de sesión del hub.

## Teardown

Orden inverso al de provisión y verificación final:

```sh
terraform -chdir=environments/staging/baseline destroy -var-file=staging.tfvars \
  -var "state_bucket=<state_bucket>" -var check_images_exist=false
terraform -chdir=environments/staging/platform destroy -var-file=staging.tfvars
scripts/verificar-teardown.sh us-east-1       # exit 0 = no queda nada facturable
```

≈ 20 min. Solo permanecen el bucket de estado, el proveedor OIDC y los roles de CI (sin costo). RDS no toma
snapshot final ni tiene protección de borrado (`db_final_snapshot`, `db_deletion_protection`); actívalos si
quieres conservar datos.

Si el destroy de la plataforma se ejecuta tras un apply fallido o parcial, es seguro: destruye lo que exista y
se puede repetir hasta que converja.

## Errores frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| `ExpiredToken` / token de seguridad caducado | Credenciales temporales (SSO/sesión) caducadas o `AWS_SESSION_TOKEN` antiguo | Renueva la sesión o, con claves de usuario, `unset AWS_SESSION_TOKEN AWS_PROFILE`; repite el comando |
| `EntityAlreadyExists` al crear el proveedor OIDC | La cuenta ya tiene el proveedor de GitHub | `terraform -chdir=bootstrap apply -var create_github_oidc_provider=false` |
| `AccessDenied` en `ssm:GetParameter` (u otro permiso) | El principal no es administrador | Usa `AdministratorAccess` en una cuenta de pruebas ([permisos](#permisos-del-principal-iam-remoto)) |
| `AsgInstanceLaunchFailures ... quota for maximum Fleet Requests` | Cuota `L-1216C47A` de vCPU en 0 | Solicita ≥ 16 vCPU ([cuota](#cuota-de-vcpu-en-cuentas-nuevas)) y repite el apply |
| `InvalidBucketName` | Se pasó el literal `<state_bucket>` | Reemplaza el marcador sin `< >`: `terraform -chdir=bootstrap output state_bucket` |
| `Unauthorized` en `kubectl` | Tu ARN no está en `cluster_admin_principal_arns` (con SSO, debe ser el del rol) | Añádelo en `staging.tfvars`, repite el apply de la plataforma y `aws eks update-kubeconfig` |
| `Can't locate revision` (Alembic) | El Job de migración se recreó con una imagen anterior a la que corre | Pasa en `image_tags` el SHA desplegado ([Baseline](#baseline)) |
| Push a ECR rechazado por tag inmutable | Ya existe una imagen con ese SHA | No re-publiques el mismo SHA; haz un commit nuevo o usa otro tag |

## Eliminar todo de la cuenta (limpieza total)

Solo cuando abandones la cuenta. Normalmente el bootstrap **no** se destruye: no cuesta y evita repetir la
configuración. Orden estricto: **baseline → plataforma → verificar-teardown → (solo al final) bootstrap**.

1. Baseline y plataforma: los dos `destroy` de [Teardown](#teardown).
2. `scripts/verificar-teardown.sh us-east-1` debe terminar con código 0.
3. Bootstrap. El bucket de estado tiene versionado y `force_destroy = false`, así que Terraform **no** lo borra
   mientras contenga objetos, versiones o delete markers (el código no usa `prevent_destroy`). Además, el
   estado del bootstrap vive en ese mismo bucket, por lo que primero hay que devolverlo a local:

   ```sh
   # a) En bootstrap/versions.tf vuelve a comentar el bloque backend "s3" y migra el estado a local
   terraform -chdir=bootstrap init -migrate-state

   # b) Vacía el bucket incluidas TODAS las versiones y delete markers (`aws s3 rm --recursive` no basta)
   BUCKET=$(terraform -chdir=bootstrap output -raw state_bucket)
   aws s3api delete-objects --bucket "$BUCKET" --delete "$(aws s3api list-object-versions --bucket "$BUCKET" \
     --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json)"
   aws s3api delete-objects --bucket "$BUCKET" --delete "$(aws s3api list-object-versions --bucket "$BUCKET" \
     --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json)"
   # Repite hasta que list-object-versions no devuelva nada (máx. 1000 por llamada; un resultado null
   # indica que no queda ese tipo). Alternativa: botón Empty en la consola de S3.

   # c) Destruye (con el mismo valor de create_github_oidc_provider que usaste al crear)
   terraform -chdir=bootstrap destroy -var create_github_oidc_provider=<true|false>
   ```

   Con `create_github_oidc_provider=false` el proveedor OIDC (que no gestiona este código) se conserva.
4. Comprobación manual en la consola, en `us-east-1` y en cualquier otra región usada: EKS, RDS (y snapshots),
   ElastiCache, NAT gateways, Elastic IPs, ECR, Secrets Manager y buckets S3. Cost Explorer (filtrado por la
   etiqueta `Project`) confirma que el gasto deja de crecer.

## Notas operativas

- Los secretos usan `recovery_window_in_days = 0` y ECR `force_delete = true`, para poder recrear todo al día siguiente.
- El nombre de la imagen es inmutable por tag: re-ejecutar un job de CI para el mismo SHA falla al hacer push.
- No existen volúmenes persistentes ni Services `LoadBalancer` (los `NodePort` del borde no crean balanceadores), así que nada bloquea el destroy.
- Flujo de ramas y commits: ver [CONTRIBUTING.md](CONTRIBUTING.md) (`feat(HA04): …`, `ci(HA04): …`).
