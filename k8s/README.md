# Kubernetes local

Entorno de practica: kind en Docker Desktop (contenedores Linux), un nodo Kubernetes
1.35.8, Traefik como controlador Ingress y Metrics Server para el HPA. No crea
recursos cloud ni demuestra alta disponibilidad entre maquinas.

## Preparar y desplegar desde PowerShell

Desde la raiz del proyecto, con Docker Desktop iniciado:

```powershell
python scripts/install_tools.py
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start_local_k8s.ps1
```

El instalador descarga kind 0.33.0, kubectl 1.35.8 y Helm 3.19.0 desde fuentes
oficiales, verifica SHA-256 y guarda los binarios en `.tools/`. Requiere Windows
amd64. No modifica PATH ni instala herramientas globales.

El script crea exclusivamente el cluster `proyecto-devops`, instala Metrics Server
0.9.0 y el chart Traefik 41.6.0, y aplica los manifiestos. Puede volver a ejecutarse.
Guarda credenciales y cache Helm en `.local/`, excluida de Git, y no cambia el
contexto de tu kubeconfig global. El parametro ExecutionPolicy solo afecta a ese proceso.

## Como llega una solicitud

```text
localhost:8080 -> puerto 30080 del nodo kind -> Traefik
              -> Ingress api -> Service api:80 -> Pod API:8000
```

Abrir http://localhost:8080/docs. El Ingress espera el host `localhost` y no requiere
editar el archivo hosts. El puerto del host solo se publica en 127.0.0.1; este
laboratorio usa HTTP local, no TLS publico.

```powershell
$env:KUBECONFIG = "$PWD\.local\kubeconfig"
.\.tools\kubectl.exe --context kind-proyecto-devops get nodes
.\.tools\kubectl.exe --context kind-proyecto-devops -n devops get pods,svc,ingress,hpa
Invoke-RestMethod 'http://localhost:8080/health'
Invoke-RestMethod 'http://localhost:8080/api/convert?celsius=20'
(Invoke-WebRequest 'http://localhost:8080/metrics').Content
.\.tools\kubectl.exe --context kind-proyecto-devops -n devops top pods
```

La API se descarga de GHCR con digest fijo. Actualizar `deployment.yaml` con el
digest de una nueva imagen cuando se desee desplegar otra version, y aplicar:

```powershell
.\.tools\kubectl.exe --context kind-proyecto-devops apply -k k8s
.\.tools\kubectl.exe --context kind-proyecto-devops -n devops rollout status deployment/api
```

## Que define cada archivo

- `namespace.yaml`: separa los recursos de la aplicacion en `devops`.
- `deployment.yaml`: mantiene los Pods, usa startup/readiness/liveness probes y un
  usuario sin privilegios. Sistema de archivos de solo lectura con `/tmp` temporal.
- `service.yaml`: direccion interna estable que distribuye trafico a Pods listos.
- `ingress.yaml`: ruta HTTP mediante el controlador Traefik.
- `hpa.yaml`: ajusta entre 1 y 3 replicas, con objetivo CPU 60% del request de 100m
  (aproximadamente 60m por replica). No representa el 60% del CPU de tu PC.
- `local/`: configuracion especifica de kind, controlador, metricas y prueba de carga.

Las probes de Kubernetes reemplazan el uso del HEALTHCHECK de Docker en este
entorno. Metrics Server obtiene CPU/memoria del kubelet; no usa nuestro `/metrics`.
Prometheus consumira ese endpoint en una etapa posterior.

## Demostrar el HPA

Con KUBECONFIG configurado como arriba:

```powershell
.\.tools\kubectl.exe --context kind-proyecto-devops apply -f k8s/local/load-test.yaml
.\.tools\kubectl.exe --context kind-proyecto-devops -n devops get hpa,pods -w
```

El Job genera trafico HTTP interno durante 180 segundos con 16 clientes. Termina
automaticamente, tiene un limite total de 240 segundos y Kubernetes lo limpia
10 minutos despues. Para detener la observacion usar Ctrl+C (no detiene el Job).
La ventana de reduccion del HPA es de 60 segundos; la bajada no es inmediata.

```powershell
.\.tools\kubectl.exe --context kind-proyecto-devops -n devops logs job/api-load-test
.\.tools\kubectl.exe --context kind-proyecto-devops -n devops describe hpa api
```

Para repetir la prueba antes de la limpieza automatica, borrar solo el Job anterior:
`kubectl --context kind-proyecto-devops -n devops delete job api-load-test` usando
el binario local. No agregar el Job al kustomization principal: es una prueba temporal.

## Particularidades del laboratorio

Docker Desktop de este equipo usa cgroups v1. El kind.yaml incluye
`failCgroupV1: false` como compatibilidad temporal; Kubernetes 1.35 lo rechaza
por defecto. Al migrar Docker a cgroups v2 se puede quitar ese parche.
Referencia: https://kubernetes.io/docs/concepts/architecture/cgroups/


Metrics Server usa `--kubelet-insecure-tls` por los certificados autofirmados de kind.
Ese parche esta aislado en `local/metrics-server/kustomization.yaml`: no reutilizarlo
en cloud. El archivo components.yaml corresponde al release oficial 0.9.0:
https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml

Traefik se eligio como controlador mantenido; Ingress NGINX fue retirado en 2026.
Documentacion: https://kind.sigs.k8s.io/docs/user/quick-start/
y https://github.com/traefik/traefik-helm-chart

## Liberar recursos

Cuando termines el laboratorio, este comando elimina **solo** el cluster del proyecto
y todos sus recursos Kubernetes:

```powershell
.\.tools\kind.exe delete cluster --name proyecto-devops
```

Los manifiestos e imagen de GHCR se conservan. El script de inicio recrea el entorno.
Esto libera los recursos locales; FinOps cloud se implementara con Terraform.


## Validacion realizada

- Manifiestos aceptados por Kubernetes mediante `apply --dry-run=server -k k8s`.
- `/health`, conversion, `/metrics` y `/docs` responden HTTP 200 a traves del Ingress.
- Prueba de carga: 78030 solicitudes correctas, 0 errores, durante 180 segundos.
- HPA: 1 replica inicial, 3 bajo carga y regreso a 1 tras finalizar.
- Evidencias: `docs/evidence/kubernetes-local.json`, `kubernetes-load-test.txt`,
  `kubernetes-hpa.txt` y `kubernetes-final-state.txt`.
- La aplicacion queda ejecutandose en el cluster local al finalizar la validacion.
