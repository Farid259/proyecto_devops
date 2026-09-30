# Acceso a la API desplegada en AWS por tunel

> Estado actual: laboratorio AWS destruido y verificado el 2026-09-30. El acceso por tunel ya no esta disponible. Las instrucciones se conservan para un futuro despliegue.

## Que estamos probando

```text
Navegador o cliente HTTP en tu PC
  -> http://localhost:18080
  -> kubectl port-forward autenticado contra EKS
  -> Service traefik / pod Traefik en AWS
  -> Ingress api (host localhost)
  -> Service api -> pod FastAPI en el nodo EC2 de EKS
```

La API se ejecuta en AWS. No hace falta iniciar uvicorn, Docker ni kind en tu PC.
El tunel requiere AWS CLI, kubectl, una sesion AWS valida y conectividad al cluster.
No ofrece una URL publica: solo escucha en 127.0.0.1 en la PC que lo ejecuta.
Traefik usa ClusterIP; no se provisiona un balanceador de AWS.

| Entorno | Contexto Kubernetes | Kubeconfig | URL |
|---|---|---|---|
| AWS | proyecto-devops-aws | .local/kubeconfig-aws | http://localhost:18080/docs |
| kind local | kind-proyecto-devops | .local/kubeconfig | http://localhost:8080/docs |

El endpoint https://...eks.amazonaws.com es la API administrativa de Kubernetes.
No sirve los endpoints FastAPI: abrir /docs alli puede devolver 401 Unauthorized.

## 1. Preparar la terminal

Abrir PowerShell en la raiz del proyecto:

```powershell
Set-Location C:\Users\farid\Desktop\DevOps
$env:AWS_PROFILE = "devops"
aws sts get-caller-identity --profile devops
```

La identidad esperada es el usuario IAM devops-lab de la cuenta del laboratorio.
Si la sesion vencio, renovarla con `aws login --profile devops` y autorizar
con devops-lab en el navegador. No pegar credenciales en archivos del proyecto.
Si aws no se reconoce, reabrir VS Code/PowerShell tras instalar AWS CLI.

## 2. Configurar el acceso a EKS

Ejecutar al preparar otra PC o si falta el kubeconfig (tambien se puede repetir):

```powershell
New-Item -ItemType Directory -Force .local | Out-Null
aws eks update-kubeconfig --region us-east-1 --name proyecto-devops-lab --alias proyecto-devops-aws --profile devops --kubeconfig .local/kubeconfig-aws
.\.tools\kubectl.exe --kubeconfig .local/kubeconfig-aws --context proyecto-devops-aws get nodes
.\.tools\kubectl.exe --kubeconfig .local/kubeconfig-aws --context proyecto-devops-aws -n devops get pods
```

El nodo debe estar Ready y el pod api Running, con READY 1/1.
El kubeconfig separado evita cambiar el contexto del laboratorio kind.
.local/ esta excluido de Git. El endpoint de EKS admite solo la IP publica /32
configurada en terraform/terraform.tfvars como admin_cidr.

## 3. Abrir el tunel

```powershell
.\.tools\kubectl.exe --kubeconfig .local/kubeconfig-aws --context proyecto-devops-aws -n traefik port-forward service/traefik 18080:80 --address 127.0.0.1
```

Esperar `Forwarding from 127.0.0.1:18080`. Dejar esa terminal abierta.
Se reenvia al controlador Ingress para probar tambien el enrutamiento Traefik.
Usar **localhost** en la URL: el Ingress exige ese host; usar 127.0.0.1 como
host HTTP puede devolver 404. El puerto local 18080 evita interferir con kind.

## 4. Probar desde el navegador o desde otra terminal

- Swagger: http://localhost:18080/docs
- Salud: http://localhost:18080/health
- Conversion: http://localhost:18080/api/convert?celsius=20
- Metricas: http://localhost:18080/metrics

```powershell
Invoke-RestMethod "http://localhost:18080/health"
Invoke-RestMethod "http://localhost:18080/api/convert?celsius=20"
```

Resultados esperados: status=ok; celsius=20, fahrenheit=68, kelvin=293.15.
En Swagger, seleccionar GET /api/convert > Try it out > ingresar celsius > Execute.
Estos requests llegan al pod de AWS mientras el tunel esta activo.

## 5. Cerrar y volver a abrir

Presionar Ctrl+C en la terminal del port-forward. Para volver a entrar, repetir
el comando del paso 3. Si el pod Traefik se reinicia, puede ser necesario reabrirlo.
El tunel de la primera validacion se inicio en segundo plano: si ya funciona la URL,
no es necesario abrir otro. Para identificarlo y cerrarlo manualmente:

```powershell
Get-CimInstance Win32_Process -Filter "Name='kubectl.exe'" |
  Select-Object ProcessId, CommandLine
```

Identificar exclusivamente el proceso que contiene `proyecto-devops-aws`,
`port-forward`, `service/traefik` y `18080:80`. Luego ejecutar
`Stop-Process -Id <PID_VERIFICADO>` reemplazando el marcador por su numero.
No detener otros procesos kubectl.

**Cerrar el tunel no apaga EKS ni EC2 y no detiene sus cargos.**
Para eliminar el laboratorio, seguir [Costos y cierre](../../terraform/README.md#costos-y-cierre).
Conservar terraform/terraform.tfstate hasta completar y verificar la destruccion.

## Problemas frecuentes

| Sintoma | Comprobacion |
|---|---|
| Conexion rechazada en localhost | Abrir el tunel y mantener su terminal activa. |
| Puerto 18080 ocupado | Puede ser el tunel anterior. Identificar el proceso; alternativamente usar 18081:80 y navegar a localhost:18081. |
| 401 en la URL de EKS | Es la API administrativa. Para FastAPI usar localhost:18080/docs. |
| Unauthorized/ExpiredToken en kubectl | Renovar la sesion devops y verificar la identidad. |
| Forbidden en kubectl | Revisar EKS Access Entry y permisos Kubernetes del usuario. |
| Timeout conectando a EKS | Comprobar red y si cambio la IP publica; actualizar admin_cidr mediante un plan Terraform revisado. No abrir 0.0.0.0/0. |
| 404 de Traefik | Usar localhost como host y verificar Ingress api en namespace devops. |
| 503 de Traefik | Comprobar pod api, readiness y Service api en namespace devops. |

## Evidencia y alcance

Ver [validacion AWS](../../docs/evidence/aws-api-validation.txt): HTTP 200 en
health, conversion, docs y metrics, nodo Ready, API Running y metricas del HPA.
La evidencia corresponde a esa ejecucion; no es una comprobacion en tiempo real.
Terraform administra infraestructura; kubectl/Helm instalaron API, Metrics Server
y Traefik. Prometheus/Grafana y la prueba de carga en AWS siguen pendientes.

Evidencia de cierre: [aws-destroy-validation.txt](../../docs/evidence/aws-destroy-validation.txt).
