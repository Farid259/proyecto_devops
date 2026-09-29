# Proyecto DevOps con Python

API de conversion de temperaturas con FastAPI, sin frontend ni base de datos.

## Estado

API, entorno virtual y 18 pruebas implementadas. Validado con Python 3.14.5 en Windows.
Dockerfile implementado; construccion y ejecucion en Docker pendientes de validar.
Terraform, Kubernetes, pipeline y dashboards pendientes de implementar.

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
- `Dockerfile`: build multi-stage con etapas builder y runtime.

El siguiente paso es construir y validar la imagen Docker. Luego agregaremos Kubernetes,
Terraform, CI/CD, SAST/DAST, monitoreo, configuraciones de costos e informe final.

Referencias: [FastAPI testing](https://fastapi.tiangolo.com/tutorial/testing/)
y [Prometheus Python](https://prometheus.github.io/client_python/).


## Docker

Requiere Docker Desktop iniciado y configurado para contenedores Linux.
Desde la raiz del proyecto:

```powershell
docker build --pull -t proyecto-devops:local .
docker run --detach --name proyecto-devops-local -p 127.0.0.1:8001:8000 proyecto-devops:local
```

Usamos el puerto local 8001 para evitar conflictos con Uvicorn local en 8000.
Abrir http://127.0.0.1:8001/docs. Validar:

```powershell
Invoke-RestMethod 'http://127.0.0.1:8001/health'
Invoke-RestMethod 'http://127.0.0.1:8001/api/convert?celsius=20'
(Invoke-WebRequest 'http://127.0.0.1:8001/metrics').Content
docker inspect --format '{{.State.Health.Status}}' proyecto-devops-local
docker exec proyecto-devops-local id
docker logs proyecto-devops-local
```

Resultados esperados: salud `ok`, conversion 68 Fahrenheit y 293.15 Kelvin,
metricas HTTP y usuario con UID 10001. El healthcheck puede tardar unos 30 segundos
en pasar de `starting` a `healthy`.

Detener y eliminar exclusivamente este contenedor de prueba:

```powershell
docker stop proyecto-devops-local
docker rm proyecto-devops-local
```

### Decisiones del Dockerfile

- Base oficial `python:3.14.7-slim-bookworm`: Python 3.14 como en desarrollo,
  con una revision de mantenimiento mas reciente. La etiqueta no fija un digest.
- `builder` instala dependencias de ejecucion en `/opt/venv` usando wheels.
  Si no existe un wheel para la plataforma, el build falla de forma explicita.
- `runtime` copia ese entorno y `app/`; no incorpora pruebas ni dependencias de desarrollo.
- Se copia requirements antes que el codigo para reutilizar la capa de dependencias.
- Usuario sin privilegios, logs sin buffering y healthcheck con la biblioteca estandar.
- Un worker, sin `--reload`, mantiene las metricas en un solo proceso.
- `.dockerignore` excluye .venv, Git, configuraciones locales y archivos sensibles.
- El entorno virtual local de Windows no se copia a la imagen Linux.

Estado de validacion: no se pudo construir ni arrancar la imagen desde la sesion
asistida por falta de acceso al motor Docker de Windows. Los comandos anteriores
quedan pendientes de ejecutar en la terminal del usuario.

Referencias: [builds multi-stage](https://docs.docker.com/get-started/docker-concepts/building-images/multi-stage-builds/)
y [imagen oficial de Python](https://hub.docker.com/_/python).
