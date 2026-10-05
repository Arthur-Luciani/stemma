"""`GET /ws`: um socket por cliente com os eventos de todas as sessões (o frontend filtra)."""

import asyncio
import contextlib
from typing import Any

from fastapi import APIRouter, FastAPI, WebSocket, WebSocketDisconnect
from pydantic import TypeAdapter

from app.schemas.events import LiveEvent
from app.services.events import EventBus, Subscription

router = APIRouter(tags=["events"])


@router.websocket("/ws")
async def live_events(websocket: WebSocket) -> None:
    bus: EventBus = websocket.app.state.event_bus
    await websocket.accept()
    with bus.subscribe() as subscription:
        sender = asyncio.create_task(_forward(websocket, subscription))
        try:
            # O cliente não manda nada; ler serve para perceber a desconexão.
            while True:
                await websocket.receive_text()
        except WebSocketDisconnect:
            pass
        finally:
            sender.cancel()
            with contextlib.suppress(asyncio.CancelledError, Exception):
                await sender


async def _forward(websocket: WebSocket, subscription: Subscription) -> None:
    while True:
        await websocket.send_json(await subscription.get())


def add_event_schemas(schema: dict[str, Any]) -> dict[str, Any]:
    """Põe `LiveEvent` (e os tipos que ele usa) em `components.schemas` do OpenAPI, para o
    frontend gerar os tipos dos eventos do `/ws` junto com os da API."""
    event_schema = TypeAdapter(LiveEvent).json_schema(
        ref_template="#/components/schemas/{model}", mode="serialization"
    )
    components = schema.setdefault("components", {}).setdefault("schemas", {})
    for name, definition in event_schema.pop("$defs", {}).items():
        components.setdefault(name, definition)
    components["LiveEvent"] = event_schema
    return schema


def install_event_schemas(app: FastAPI) -> None:
    original = app.openapi

    def openapi() -> dict[str, Any]:
        if app.openapi_schema is None:
            app.openapi_schema = add_event_schemas(original())
        return app.openapi_schema

    app.openapi = openapi  # type: ignore[method-assign]
