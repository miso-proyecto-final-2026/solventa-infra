"""Crea los topics del bus de eventos en MSK (HS2). Idempotente: lo que ya existe se deja como está.

Uso: python crear_topics.py topics.json
Entorno: KAFKA_BOOTSTRAP_SERVERS (obligatorio), AWS_REGION (para IAM) y KAFKA_SEGURIDAD
(`IAM` por defecto; `PLAINTEXT` solo para probar contra un Kafka local).
"""

import asyncio
import json
import os
import ssl
import sys

from aiokafka.admin import AIOKafkaAdminClient, NewTopic
from aiokafka.errors import TopicAlreadyExistsError


def _cliente() -> AIOKafkaAdminClient:
    comunes = {
        "bootstrap_servers": os.environ["KAFKA_BOOTSTRAP_SERVERS"].split(","),
        "client_id": "solventa-kafka-topics",
        "request_timeout_ms": 30000,
    }
    if os.environ.get("KAFKA_SEGURIDAD", "IAM").upper() == "PLAINTEXT":
        return AIOKafkaAdminClient(security_protocol="PLAINTEXT", **comunes)

    from aiokafka.abc import AbstractTokenProvider
    from aws_msk_iam_sasl_signer import MSKAuthTokenProvider

    region = os.environ["AWS_REGION"]

    class ProveedorTokenIam(AbstractTokenProvider):
        async def token(self):
            # La firma usa las credenciales de Pod Identity y puede bloquear un instante: fuera del bucle de eventos.
            cargador = asyncio.get_running_loop()
            token, _ = await cargador.run_in_executor(None, MSKAuthTokenProvider.generate_auth_token, region)
            return token

    return AIOKafkaAdminClient(
        security_protocol="SASL_SSL",
        ssl_context=ssl.create_default_context(),
        sasl_mechanism="OAUTHBEARER",
        sasl_oauth_token_provider=ProveedorTokenIam(),
        **comunes,
    )


async def crear(topics: dict[str, dict]) -> int:
    admin = _cliente()
    await admin.start()
    try:
        existentes = set(await admin.list_topics())
        nuevos = [
            NewTopic(
                name=nombre,
                num_partitions=cfg["partitions"],
                replication_factor=cfg["replication_factor"],
                topic_configs={"retention.ms": str(cfg["retention_ms"])},
            )
            for nombre, cfg in topics.items()
            if nombre not in existentes
        ]
        if nuevos:
            try:
                await admin.create_topics(nuevos)
            except TopicAlreadyExistsError:
                # Otra ejecución los creó entre la lectura y la creación: se verifica abajo.
                pass
        final = set(await admin.list_topics())
    finally:
        await admin.close()

    faltan = sorted(set(topics) - final)
    print(f"topics declarados: {len(topics)} | ya existían: {len(set(topics) & existentes)} | creados ahora: {len(nuevos)}")
    if faltan:
        print(f"ERROR: no existen tras crearlos: {', '.join(faltan)}", file=sys.stderr)
        return 1
    print("OK: todos los topics existen")
    return 0


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as f:
        declarados = json.load(f)
    sys.exit(asyncio.run(crear(declarados)))
