# Proyecto DevOps con Python

API de conversion de temperaturas con FastAPI, sin frontend ni base de datos.

## Estado

API, entorno virtual y 26 pruebas implementadas. Validado con Python 3.14.5 en Windows.
Dockerfile multi-stage validado y publicada la imagen en GitHub Container Registry.
CI con pruebas, SAST y DAST ejecutado correctamente en GitHub Actions (confirmado por el usuario).
Kubernetes local implementado con kind, Traefik, Metrics Server y HPA.
Terraform, despliegue cloud automatizado y dashboards pendientes de implementar.
DAST con ZAP validado despues de corregir las cabeceras HTTP.

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
- `.github/workflows/ci.yml`: pruebas, SAST, construccion y publicacion de imagen.
- `k8s/`: manifiestos, configuracion local y guia de Kubernetes.
- `terraform/`, `monitoring/`: preparadas, aun sin implementar.
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


## GitHub Actions: CI y publicacion de imagen

El workflow `.github/workflows/ci.yml` se ejecuta en pushes a `main`, pull requests
hacia `main` y manualmente desde Actions. Incluye tres jobs:

1. **tests**: instala dependencias, comprueba compatibilidad y ejecuta pytest.
2. **sast**: ejecuta Bandit sobre `app/`; cualquier hallazgo hace fallar el job.
3. **docker**: requiere los dos anteriores, construye la imagen, espera el healthcheck,
   comprueba endpoints y UID 10001, ejecuta DAST y publica exactamente esa imagen validada.

La publicacion solo ocurre en pushes a `main`. Los pull requests y ejecuciones
manuales validan sin publicar. Las acciones externas estan fijadas por SHA.
La autenticacion usa el `GITHUB_TOKEN` automatico con `packages: write` en el job
Docker; no se necesita crear un token personal ni una cuenta de Docker Hub.

Imagen: `ghcr.io/farid259/proyecto_devops`.
Etiquetas: `sha-<SHA completo del commit>` y `latest`. Para futuros despliegues,
preferir la etiqueta del commit o el digest en lugar de `latest`.

### Primera ejecucion

Subir los cambios a `main` y abrir:
https://github.com/Farid259/proyecto_devops/actions

Revisar que los tres jobs terminen correctamente. Cada ejecucion guarda artifacts
con el reporte pytest, reporte JSON de Bandit y logs/inspeccion del contenedor
por 14 dias. Descargar los necesarios para el informe antes de que caduquen.
La imagen aparecera en Packages del perfil/repositorio al publicarse.

La visibilidad del paquete GHCR se gestiona por separado: un repositorio publico
no garantiza una imagen publica. Para permitir descargas anonimas, comprobar en
Package settings que su visibilidad sea Public. Si permanece privado, los futuros
clientes y el cluster necesitaran autenticacion para descargarla.

Si GitHub deniega el push del paquete, revisar los permisos efectivos de Actions
y que el paquete, si ya existia, permita acceso a este repositorio.

### Ejecutar SAST localmente

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements-security.txt
.\.venv\Scripts\python.exe -m bandit -r app
```

Bandit analiza patrones de seguridad del codigo Python. No reemplaza DAST ni un
analisis de vulnerabilidades de dependencias o de la imagen. DAST se ejecuta
con ZAP como se describe a continuacion; los otros analisis quedan pendientes.

Validacion local de esta etapa: 18 pruebas aprobadas y Bandit sin hallazgos.
La ejecucion completa del workflow y la publicacion en GHCR requieren el primer push.

Referencia: https://docs.github.com/en/actions/tutorials/publish-packages/publish-docker-images


## DAST con OWASP ZAP

El job Docker ejecuta un escaneo activo de la API temporal del runner, despues de
las pruebas funcionales y antes del login y la publicacion en GHCR. Usa la imagen
oficial `ghcr.io/zaproxy/zaproxy:stable` (etiqueta actualizable, no fijada por digest).

ZAP importa `http://127.0.0.1:18000/openapi.json` y envia solicitudes de prueba a
las operaciones declaradas. `--network host` permite alcanzar el puerto local del
runner Linux; no necesita publicar la API en Internet. El escaneo solo apunta al
contenedor efimero de esta ejecucion, no a produccion ni a servicios ajenos.

La cobertura depende de OpenAPI: `/metrics` tiene `include_in_schema=False`, por lo
que no forma parte del escaneo importado. Su funcionamiento se valida por separado
con la prueba del contenedor. Tampoco se analiza aun un Ingress ni un cluster.

### Criterio de bloqueo

Se conserva la politica predeterminada de ZAP: cualquier alerta WARN o FAIL, asi
como errores del escaner, hace fallar el paso y bloquea la publicacion. No se usan
`-I`, reglas IGNORE ni `continue-on-error`. El primer analisis puede detectar
advertencias de cabeceras u otros hallazgos: revisar el reporte antes de corregirlos
o justificar una excepcion especifica. No considerar la integracion como aprobada
hasta que termine el primer analisis real.

ZAP devuelve 0 sin hallazgos bloqueantes, 1 con FAIL, 2 con WARN y 3 ante otros errores.
El paso tiene un limite total de 15 minutos; `-T 5` limita la espera de arranque y
analisis pasivo, no la duracion total del escaneo activo.

### Evidencias

El artifact `zap-results` conserva `report.html`, `report.json` y `report.md` durante
14 dias, incluso si el analisis detecta alertas. Si falla antes de producir reportes,
consultar los logs del paso. Los logs de la API siguen en `docker-results`.
Descargar los reportes desde la ejecucion en Actions para el informe final.

Estado: workflow validado estaticamente; ejecucion real pendiente en GitHub Actions
porque esta sesion no tiene acceso al motor Docker local.

Referencia: https://www.zaproxy.org/docs/docker/api-scan/


### Correccion de hallazgos ZAP 10021 y 90004

La API agrega `X-Content-Type-Options: nosniff` para impedir que el navegador
interprete la respuesta con un tipo distinto del Content-Type declarado, y
`Cross-Origin-Resource-Policy: same-origin` para restringir cargas no-CORS desde
otros origenes. CORP no reemplaza autenticacion ni configura permisos CORS.
Si se incorpora un frontend en otro origen, revisar esta politica junto con CORS.

Las pruebas comprueban ambas cabeceras en los endpoints informados por ZAP,
la documentacion, metricas y respuestas 404/422. Validacion local: 26 pruebas
aprobadas y Bandit sin hallazgos. La cache local de pytest emitio una advertencia
de escritura; las pruebas se ejecutaron correctamente. El nuevo resultado de
ZAP queda pendiente de reconstruir y analizar la imagen mediante el pipeline.


## Kubernetes local

Guia completa: [k8s/README.md](k8s/README.md).
El entorno se prepara con `python scripts/install_tools.py` y
`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start_local_k8s.ps1`.

Una vez iniciado, abrir http://localhost:8080/docs y consultar el estado:

```powershell
$env:KUBECONFIG = "$PWD\.local\kubeconfig"
.\.tools\kubectl.exe --context kind-proyecto-devops -n devops get pods,svc,ingress,hpa
.\.tools\kubectl.exe --context kind-proyecto-devops -n devops top pods
```

Se usa kubectl local 1.35.8, compatible con el cluster. El kubectl incluido con Docker
puede ser antiguo. `.tools/` y `.local/` estan excluidas de Git y de la imagen Docker.
Kubeconfig contiene credenciales locales y no debe compartirse.

La imagen se fija por digest de GHCR; Ingress usa Traefik. El HPA escala de 1 a 3
replicas por CPU. Metrics Server permite el HPA; Prometheus y Grafana siguen pendientes.
La guia explica los parches locales de cgroups v1 y certificados del kubelet.
