# Proyecto DevOps con Python

API de conversion de temperaturas con FastAPI, sin frontend ni base de datos.

## Estado

API, entorno virtual y 18 pruebas implementadas. Validado con Python 3.14.5 en Windows.
Dockerfile, Terraform, Kubernetes, pipeline y dashboards pendientes de implementar.

## Preparar el entorno en PowerShell

Para una instalacion nueva, desde la raiz del proyecto:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
```

Las dependencias directas estan fijadas. Las transitivas aun no tienen un lock
compartido entre plataformas. La captura del entorno Windows esta en
`docs/evidence/dependencies-windows.txt`.

En VS Code: `Ctrl+Shift+P`, `Python: Select Interpreter`, seleccionar
`.venv\Scripts\python.exe`. La configuracion del proyecto habilita pytest.
Los comandos usan el interprete explicito y no requieren activar scripts.
La activacion opcional es `.\.venv\Scripts\Activate.ps1`.

## Ejecutar

```powershell
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload
```

Abrir http://127.0.0.1:8000/docs. Detener con Ctrl+C. `--reload` es para desarrollo.
Usar un worker por proceso para estas metricas; en Kubernetes escalaremos con Pods.

| Endpoint | Resultado |
| --- | --- |
| `GET /` | Nombre, version y enlace a docs |
| `GET /health` | `{"status":"ok"}`: disponibilidad del proceso |
| `GET /api/convert?celsius=20` | `{"celsius":20.0,"fahrenheit":68.0,"kelvin":293.15}` |
| `GET /metrics` | Metricas Prometheus |
| `GET /docs` | Documentacion interactiva |

La conversion admite valores finitos entre -273.15 y 1000000 Celsius. El minimo
es el cero absoluto; el maximo es un limite operativo. Los resultados se redondean
a dos decimales. Los valores ausentes o invalidos devuelven HTTP 422.

## Validar

```powershell
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m pip check
```

Las pruebas verifican salud, documentacion, conversiones, entradas invalidas y metricas.
Usan TestClient y no necesitan un servidor iniciado manualmente.

Para generar trafico real mientras Uvicorn esta ejecutandose:

```powershell
Invoke-RestMethod 'http://127.0.0.1:8000/api/convert?celsius=20'
Invoke-RestMethod 'http://127.0.0.1:8000/health'
(Invoke-WebRequest 'http://127.0.0.1:8000/metrics').Content
```

## Metricas

- `http_requests_total`: solicitudes por metodo, ruta y estado HTTP; permite contar errores.
- `http_request_duration_seconds`: histograma de duracion por metodo y ruta.
- `/metrics` no se cuenta como trafico; rutas inexistentes se agrupan como `unmatched`.
- Los contadores se reinician con el proceso; Prometheus guardara su historial.

## Carpetas y siguientes etapas

- `app/`: API Python.
- `tests/`: pruebas.
- `docs/evidence/`: resultados y dependencias del entorno validado.
- `k8s/`, `terraform/`, `monitoring/`, `.github/workflows/`: preparadas, aun sin implementar.
- `Dockerfile`: marcador pendiente de sustituir por un build multi-stage funcional.

El siguiente paso es crear y validar la imagen Docker. Luego agregaremos Kubernetes,
Terraform, CI/CD, SAST/DAST, monitoreo, configuraciones de costos e informe final.

Referencias: [FastAPI testing](https://fastapi.tiangolo.com/tutorial/testing/)
y [Prometheus Python](https://prometheus.github.io/client_python/).
