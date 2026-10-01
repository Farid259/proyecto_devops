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
