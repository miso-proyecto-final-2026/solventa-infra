"""Prueba de humo del bus de eventos (HS2, criterio 4): publica un evento y lo consume de vuelta.

Entorno: KAFKA_BOOTSTRAP_SERVERS, AWS_REGION (IAM) y KAFKA_SEGURIDAD (`IAM` por defecto; `PLAINTEXT` para un Kafka local).
Sale con 0 si el evento publicado llega al consumidor dentro del tiempo límite; con 1 si no.
"""

import asyncio
import json
import os
import ssl
import sys
import time
import uuid

from aiokafka import AIOKafkaConsumer, AIOKafkaProducer

TOPIC = os.environ.get("TOPIC_HUMO", "solventa.humo")
LIMITE_S = int(os.environ.get("LIMITE_S", "60"))


def _seguridad() -> dict:
    if os.environ.get("KAFKA_SEGURIDAD", "IAM").upper() == "PLAINTEXT":
        return {"security_protocol": "PLAINTEXT"}

    from aiokafka.abc import AbstractTokenProvider
    from aws_msk_iam_sasl_signer import MSKAuthTokenProvider

    region = os.environ["AWS_REGION"]

    class ProveedorTokenIam(AbstractTokenProvider):
        async def token(self):
            token, _ = await asyncio.get_running_loop().run_in_executor(
                None, MSKAuthTokenProvider.generate_auth_token, region
            )
            return token

    return {
        "security_protocol": "SASL_SSL",
        "ssl_context": ssl.create_default_context(),
        "sasl_mechanism": "OAUTHBEARER",
        "sasl_oauth_token_provider": ProveedorTokenIam(),
    }


async def main() -> int:
    brokers = os.environ["KAFKA_BOOTSTRAP_SERVERS"].split(",")
    evento = {
        "event_id": str(uuid.uuid4()),
        "event_type": "prueba_de_humo",
        "source": "kafka-humo",
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "version": "1.0",
        "payload": {"mensaje": "hola desde un pod"},
    }
    # El grupo debe empezar por "kafka-humo": es lo único que la política de IAM le permite.
    consumidor = AIOKafkaConsumer(
        TOPIC,
        bootstrap_servers=brokers,
        group_id=f"kafka-humo-{evento['event_id'][:8]}",
        auto_offset_reset="earliest",
        enable_auto_commit=False,
        client_id="kafka-humo-consumidor",
        **_seguridad(),
    )
    productor = AIOKafkaProducer(bootstrap_servers=brokers, client_id="kafka-humo-productor", **_seguridad())
    await consumidor.start()
    await productor.start()
    try:
        inicio = time.monotonic()
        meta = await productor.send_and_wait(TOPIC, json.dumps(evento).encode(), key=b"humo")
        print(f"publicado: topic={meta.topic} partición={meta.partition} offset={meta.offset} event_id={evento['event_id']}")
        while time.monotonic() - inicio < LIMITE_S:
            lote = await consumidor.getmany(timeout_ms=2000)
            for mensajes in lote.values():
                for m in mensajes:
                    if json.loads(m.value).get("event_id") == evento["event_id"]:
                        print(f"consumido en {time.monotonic() - inicio:.2f} s (offset {m.offset})")
                        print("OK: el evento publicado llegó al consumidor")
                        return 0
        print(f"FALLO: el evento no llegó en {LIMITE_S} s", file=sys.stderr)
        return 1
    finally:
        await productor.stop()
        await consumidor.stop()


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
