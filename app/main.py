from time import perf_counter
from typing import Annotated

from fastapi import FastAPI, Query, Request, Response
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    CollectorRegistry,
    Counter,
    Histogram,
    generate_latest,
)
from pydantic import BaseModel


class TemperatureResponse(BaseModel):
    celsius: float
    fahrenheit: float
    kelvin: float


def create_app() -> FastAPI:
    """Crear una aplicación con un registro de métricas independiente."""
    api = FastAPI(title="DevOps Temperature API", version="0.1.0")
    registry = CollectorRegistry()
    requests_total = Counter(
        "http_requests_total",
        "Total de solicitudes HTTP por método, ruta y estado.",
        ["method", "route", "status"],
        registry=registry,
    )
    request_duration = Histogram(
        "http_request_duration_seconds",
        "Duración de las solicitudes HTTP en segundos.",
        ["method", "route"],
        registry=registry,
    )

    @api.middleware("http")
    async def record_metrics(request: Request, call_next):
        # El scraping de Prometheus no debe inflar las métricas de tráfico.
        if request.url.path == "/metrics":
            return await call_next(request)

        started = perf_counter()
        status = 500
        try:
            response = await call_next(request)
            status = response.status_code
            return response
        finally:
            matched_route = request.scope.get("route")
            # Agrupar URLs desconocidas evita crear etiquetas sin límite.
            route = getattr(matched_route, "path", "unmatched")
            requests_total.labels(request.method, route, str(status)).inc()
            request_duration.labels(request.method, route).observe(
                perf_counter() - started
            )

    @api.get("/")
    async def index() -> dict[str, str]:
        return {"name": api.title, "version": api.version, "docs": "/docs"}

    @api.get("/health")
    async def health() -> dict[str, str]:
        return {"status": "ok"}

    @api.get("/metrics", include_in_schema=False)
    async def metrics() -> Response:
        return Response(
            content=generate_latest(registry),
            headers={"Content-Type": CONTENT_TYPE_LATEST},
        )

    @api.get("/api/convert", response_model=TemperatureResponse)
    async def convert_temperature(
        celsius: Annotated[
            float,
            Query(
                ge=-273.15,
                le=1_000_000,
                allow_inf_nan=False,
                description="Temperatura en Celsius entre -273.15 y 1000000.",
            ),
        ],
    ) -> TemperatureResponse:
        # El máximo es un límite operativo de esta API, no un límite físico.
        return TemperatureResponse(
            celsius=celsius,
            fahrenheit=round(celsius * 9 / 5 + 32, 2),
            kelvin=round(celsius + 273.15, 2),
        )

    return api


app = create_app()
