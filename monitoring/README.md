# Monitoreo de la API

Prometheus consulta /metrics cada 15s en TODAS las replicas descubiertas mediante
el Service headless api-metrics.devops.svc.cluster.local. Grafana consulta al
Prometheus del mismo cluster. Al aplicar estos archivos en EKS desde CD, los datos
son de AWS; al aplicarlos en kind son locales. No requiere acceso IAM ni RBAC.

## Instalacion local

```powershell
.\.tools\kubectl.exe --kubeconfig .local/kubeconfig --context kind-proyecto-devops apply -k monitoring
.\.venv\Scripts\python.exe scripts/verify_monitoring.py --kubectl .tools/kubectl.exe --kubeconfig .local/kubeconfig --context kind-proyecto-devops
```

start_local_k8s.ps1 tambien instala el monitoreo. CD ejecuta apply, espera ambos
Deployments y verifica scraping, dashboard y consulta Grafana -> Prometheus.
No se ha desplegado esta incorporacion en AWS todavia.

## Acceder (cada comando en una terminal)

```powershell
.\.tools\kubectl.exe --kubeconfig .local/kubeconfig --context kind-proyecto-devops -n monitoring port-forward service/grafana 13000:3000 --address=127.0.0.1
.\.tools\kubectl.exe --kubeconfig .local/kubeconfig --context kind-proyecto-devops -n monitoring port-forward service/prometheus 19090:9090 --address=127.0.0.1
```

- Dashboard: http://localhost:13000/d/devops-api
- Targets: http://localhost:19090/targets
- Alertas: http://localhost:19090/alerts

En AWS reemplazar kubeconfig por .local/kubeconfig-aws y contexto por
proyecto-devops-aws. AWS CLI debe estar en PATH y tener sesion valida.
Los servicios son ClusterIP, sin LoadBalancer ni Ingress publico.
Grafana permite lectura anonima Viewer a quien tenga acceso de red; no hay
administrador inicial ni credenciales predeterminadas. Es una configuracion de
laboratorio para tunel privado, no para publicar en Internet.

## Dashboard y alertas

Disponibilidad, solicitudes/s, errores 5xx/s, latencia p95 y alertas firing.
El trafico y latencia excluyen /health; las metricas necesitan trafico y varios
scrapes para mostrar tasas. Generar solicitudes en /api/convert desde Swagger.
ApiUnavailable se activa tras 1m sin replicas disponibles, incluyendo ausencia
de series. ApiHighErrorRate se activa tras 2m con mas del 5% de respuestas 5xx.
Se visualizan en Prometheus; no se configuro envio de emails, Slack ni Alertmanager.

Prueba reproducible de caida y recuperacion con series simuladas (no apaga la API):

```powershell
.\.tools\kubectl.exe --kubeconfig .local/kubeconfig --context kind-proyecto-devops -n monitoring exec deployment/prometheus -- promtool test rules /etc/prometheus/alerts.test.yml
```

## Limites y costos

Almacenamiento emptyDir: el historial se pierde si se reemplaza el pod.
Prometheus conserva como maximo 24h/512MB de bloques (WAL y otros archivos pueden
ocupar mas); volumen limitado a 1Gi. Requests totales: 200m CPU y 384Mi RAM.
Limites RAM: Prometheus 512Mi; Grafana 768Mi. Grafana usa hasta 2Gi de
almacenamiento temporal para plugins y su base de datos. Evaluar capacidad del nodo para AWS.
Grafana requiere escritura para registrar sus plugins; sigue ejecutando sin root,
sin capacidades Linux y sin token de ServiceAccount. No es alta disponibilidad.
La configuracion y el dashboard se restauran desde Git en cada despliegue.
Destruir EKS elimina estos pods. No se aprovisionan discos EBS adicionales.

Referencias:
- https://prometheus.io/docs/prometheus/latest/configuration/configuration/
- https://grafana.com/docs/grafana/latest/administration/provisioning/

## Arquitectura general

Ver [diagramas, flujo CI/CD, seguridad y ciclo de vida](../docs/architecture.md).

## Conexion automatica a AWS desde PowerShell

Desde la raiz del proyecto, usar una terminal por servicio:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/connect_aws.ps1 -Service api
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/connect_aws.ps1 -Service grafana
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/connect_aws.ps1 -Service prometheus
```

Ejecutar el primero y esperar a que abra el tunel antes de iniciar los siguientes.
API: http://localhost:18080/docs; Grafana: http://localhost:13000/d/devops-api;
Prometheus: http://localhost:19090/targets. Cada comando permanece ejecutandose.
Ctrl+C cierra solo ese tunel. No crea ni destruye el laboratorio.

El script agrega AWS CLI al PATH de su proceso, verifica la cuenta contra el
terraform.tfvars local, detecta la IPv4 publica, actualiza el /32 de EKS si cambio,
espera la actualizacion y sincroniza ADMIN_CIDR en GitHub y admin_cidr local.
Luego actualiza kubeconfig y abre el tunel en 127.0.0.1. No abre 0.0.0.0/0.
Terraform refrescara el cambio de EKS en el siguiente plan.

Requiere sesion AWS valida (aws login --profile devops), el terraform.tfvars
local, kubectl y Git con una credencial GitHub guardada con permisos sobre las
variables del entorno aws-lab. Tambien admite GH_TOKEN en la sesion. Usa esa
credencial sin imprimirla ni escribirla en archivos. No pegar tokens en Git.

Se detiene si hay workflows en ejecucion, multiples CIDR en EKS, otra cuenta o
un puerto ocupado. No ejecutar simultaneamente con Terraform/CD ni aprobar un
nuevo despliegue mientras cambia el acceso: la comprobacion no es un bloqueo
distribuido. Si GitHub falla despues del cambio AWS, informa sincronizacion
incompleta; corregirla antes de volver a desplegar. Una VPN o cambio de red durante
el tunel puede requerir cerrar y ejecutar nuevamente el script.

Opciones:

```powershell
# Solo consultar: no modifica AWS, GitHub ni archivos; no abre tuneles.
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/connect_aws.ps1 -CheckOnly
# Usar otro puerto local si 13000 esta ocupado.
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/connect_aws.ps1 -Service grafana -LocalPort 13002
```

La primera prueba realizada fue de sintaxis y CheckOnly. La ruta de escritura
completa se verificara cuando se utilice para conectar; no se simulo un cambio de
IP en AWS para probarlo.
