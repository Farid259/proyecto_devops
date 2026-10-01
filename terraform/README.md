# AWS EKS temporal

> Estado actual: laboratorio AWS destruido y verificado el 2026-09-30. El acceso por tunel ya no esta disponible. Las instrucciones se conservan para un futuro despliegue.

Estado: infraestructura desplegada con Terraform y API verificada en AWS.
Guia de acceso: [tunel a AWS](../k8s/aws/README.md).
Evidencia: [validacion de la API](../docs/evidence/aws-api-validation.txt).
El laboratorio fue eliminado posteriormente por solicitud del usuario.

## Arquitectura

- Modulo network: VPC 10.42.0.0/16, dos subredes publicas en distintas zonas,
  Internet Gateway y rutas. Sin NAT Gateway.
- Modulo eks: EKS 1.35 con soporte STANDARD y un grupo administrado de un nodo
  t3.medium Linux AL2023, disco de 20 GB. No se habilita EKS Auto Mode.
- Endpoint Kubernetes privado para los nodos; endpoint publico limitado a tu IPv4 /32.
- Administrador mediante EKS Access Entry para un ARN IAM explicito.
- Sin SSH, balanceador de AWS ni reglas de entrada publica para la aplicacion.
- El HPA escala pods, no nodos: max_size=1 limita el grupo. Si falta capacidad,
  los pods quedan Pending. Las actualizaciones administradas pueden crear nodos
  temporales adicionales. Un solo nodo no proporciona alta disponibilidad.

La politica CNI se adjunta al rol del nodo para este laboratorio; para produccion
se debe separar la identidad del CNI y endurecer el acceso a metadatos.
EKS instala los componentes de red predeterminados; Metrics Server, Traefik y
el despliegue de la API se configuran posteriormente. No aplicar los parches de kind.

## Preparacion (desde la raiz del repositorio, PowerShell)

1. Instalar Terraform con `python scripts/install_tools.py` (Windows amd64).
2. Instalar AWS CLI v2 siguiendo https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
3. Configurar un perfil AWS, preferentemente con credenciales temporales/SSO.
   No usar la cuenta root ni guardar claves en Terraform o en Git.
4. Verificar la identidad y copiar el ejemplo:

```powershell
$env:AWS_PROFILE = "devops"
aws sts get-caller-identity
Copy-Item terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Editar terraform.tfvars: cuenta real, IPv4 publica /32 y ARN IAM del administrador.
Si sts devuelve un ARN assumed-role, usar el ARN IAM real del rol (con su ruta),
no el ARN de la sesion. El perfil necesita permisos de provisionamiento de
VPC/EC2, EKS e IAM, incluido PassRole. El acceso administrador de Kubernetes
no otorga esos permisos AWS. Los valores de ejemplo no permiten un despliegue util.

```powershell
.\.tools\terraform.exe -chdir=terraform init
.\.tools\terraform.exe -chdir=terraform fmt -check -recursive
.\.tools\terraform.exe -chdir=terraform validate
.\.tools\terraform.exe -chdir=terraform plan "-out=lab.tfplan"
```

Revisar el plan y los costos antes de crear recursos. init/validate no crean
infraestructura; plan consulta AWS y requiere credenciales.

## Crear y conectar (genera costos)

```powershell
.\.tools\terraform.exe -chdir=terraform apply lab.tfplan
aws eks update-kubeconfig --region us-east-1 --name proyecto-devops-lab --alias proyecto-devops-aws --kubeconfig .local/kubeconfig-aws
.\.tools\kubectl.exe --kubeconfig .local/kubeconfig-aws --context proyecto-devops-aws get nodes
```

Los comandos usan los nombres y region predeterminados; adaptarlos si se cambian
variables. El kubeconfig AWS queda separado de kind. Si cambia tu IP publica,
actualizar admin_cidr y volver a planificar/aplicar.

Para acceder y probar la API mediante Ingress, seguir la
[guia del tunel AWS](../k8s/aws/README.md). URL: http://localhost:18080/docs.

## Costos y cierre

Estimacion orientativa us-east-1: aproximadamente USD 0.15/h para EKS con soporte
estandar, un t3.medium, una IPv4 y 20 GB de disco. Sin impuestos, transferencia,
creditos CPU T3 ni servicios adicionales. El tipo de disco lo determina la plantilla
predeterminada de EKS; no fijamos gp3 en esta primera configuracion.
No es un limite de gasto. Prometheus/Grafana pueden requerir mas capacidad.

Al terminar, guardar evidencias y revisar la destruccion:

```powershell
.\.tools\terraform.exe -chdir=terraform plan -destroy "-out=destroy.tfplan"
.\.tools\terraform.exe -chdir=terraform apply destroy.tfplan
.\.tools\terraform.exe -chdir=terraform state list
```

Verificar tambien en AWS que no quedan nodos, discos, direcciones ni el cluster.
Apagar EC2 no detiene la facturacion de EKS. No borrar el estado antes de destruir.
Si apply falla parcialmente, los recursos creados pueden seguir cobrando: revisar
el estado y destruir. Los presupuestos con alertas no frenan automaticamente el gasto.

El laboratorio usa estado remoto en S3 cifrado, versionado y bloqueo use_lockfile.
Los planes y respaldos locales quedan fuera de Git; versionar .terraform.lock.hcl.
El CD despliega con aprobacion y permite iniciar la destruccion manual desde
Actions. Este es el mecanismo de cierre elegido; no se incluye apagado programado.

Referencias:
- https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
- https://registry.terraform.io/providers/hashicorp/aws/6.38.0/docs/resources/eks_cluster
- https://aws.amazon.com/eks/pricing/


## Permisos del laboratorio (una sola politica)

La [plantilla IAM](iam/lab-provision-policy.json.tftpl) usa `${account_id}`.
Terraform la completa con `var.account_id`, definido en `terraform.tfvars`
(excluido de Git) o mediante `TF_VAR_account_id`. El local
`local.lab_provision_policy` en `iam-policy.tf` contiene el JSON resultante.
No crea ni modifica politicas en AWS por si solo.

Para generar el JSON desde la raiz del repositorio (PowerShell), despues de
`terraform init` y de configurar las variables locales:

```powershell
New-Item -ItemType Directory -Force .local | Out-Null
$policyOutput = 'jsonencode(jsondecode(local.lab_provision_policy))' | .\.tools\terraform.exe -chdir=terraform console
if ($LASTEXITCODE -ne 0) { throw 'No se pudo generar la politica' }
$policyJson = ($policyOutput -join "`n") | ConvertFrom-Json
$null = $policyJson | ConvertFrom-Json
[System.IO.File]::WriteAllText(
    (Join-Path (Get-Location) '.local/lab-provision-policy.json'),
    $policyJson,
    [System.Text.UTF8Encoding]::new($false)
)
```

Este comando evalua la plantilla; no ejecuta apply ni crea infraestructura.
Versionar la plantilla, no el JSON generado dentro de `.local/`.
No pegar `${account_id}` directamente en IAM: usar el JSON generado.

En el futuro workflow CD, el job que use el entorno `aws-lab` podra recibir:

```yaml
env:
  TF_VAR_account_id: ${{ vars.AWS_ACCOUNT_ID }}
```

Configurar `AWS_ACCOUNT_ID` como variable del entorno en GitHub. Es un
identificador, no una credencial. La autenticacion OIDC y el rol con permisos
se configuran por separado; esta plantilla no habilita el acceso desde Actions.
El ejemplo anterior documenta la integracion prevista, aun no implementada.

Usar el JSON generado como politica administrada por el cliente, nombre
DevOpsLabProvision. Desde una identidad administradora: IAM > Politicas >
Crear politica > JSON > pegar el contenido generado > crear.
Para una politica existente, editarla en lugar de crear otra.

Luego IAM > Usuarios > devops-lab > Agregar permisos > Adjuntar politicas directamente
> seleccionar DevOpsLabProvision. Conservar SignInLocalDevelopmentAccess.
La politica anterior DevOpsLabPlanRead es redundante y se puede retirar.
No usar politica insertada: el documento supera el limite agregado de 2048
caracteres de politicas insertadas de un usuario. Cabe en el limite de 6144 de
una politica administrada.

Alcance: consultas EC2 regionales; creacion de red con etiqueta Project;
mutaciones de red con esa etiqueta; cl?ster, nodegroups y accesos EKS con nombre
proyecto-devops-lab; dos roles IAM del laboratorio y solo cuatro politicas AWS
permitidas; PassRole limitado a esos roles y servicios; creacion de roles
vinculados de EKS/nodegroups/Auto Scaling si todavia no existen.
CreateCluster no admite ARN de recurso: se limita por region y etiqueta requerida.
Las etiquetas no son una barrera contra un administrador malicioso: esta es una
politica de operador de laboratorio, no un limite de gasto ni de cantidad de nodos.
Permite acciones que generan costos al ejecutarse. Adjuntarla no despliega recursos.

Estado: politica preparada localmente, nombres de acciones verificados contra
la referencia oficial AWS; politica actualizada y apply completado. Destroy no probado.
Un plan correcto no garantiza todos los permisos en ejecucion. Si AWS devuelve
AccessDenied, revisar la accion/recurso concreto antes de ampliar permisos.
Alcance actual: infraestructura Terraform existente. No incluye backend S3 remoto,
OIDC para CI/CD, balanceadores, ni futuros servicios de monitoreo administrado.
Los roles vinculados al servicio creados automaticamente pueden permanecer en IAM
tras terraform destroy; son compartidos por el servicio y no se eliminan aqui.

Perfil: AWS_PROFILE=devops. El JSON del plan y los tfvars reales no se versionan.
La creacion de infraestructura requiere revision del plan y autorizacion del usuario.

Referencia: https://docs.aws.amazon.com/service-authorization/latest/reference/

Validacion del plan: [evidencia](../docs/evidence/terraform-plan-validation.txt).
Se verifico el perfil devops y se guardaron variables locales con la IP publica /32.
Si cambia la IP o la configuracion, regenerar el plan antes de aplicar.

## Historial de despliegue

Los primeros intentos se detuvieron por permisos de red y consulta de roles
internos de EKS. Las correcciones se incorporaron a la politica y se completo
el despliegue conservando el estado parcial. Evidencias:

- [Intentos iniciales](../docs/evidence/terraform-apply-validation.txt).
- [Despliegue y API verificados](../docs/evidence/aws-api-validation.txt).

API, Metrics Server y Traefik se instalaron con kubectl/Helm.
El acceso elegido es un tunel local al Ingress remoto, sin balanceador AWS:
[abrir, probar, cerrar y diagnosticar el tunel](../k8s/aws/README.md).

Evidencia de cierre: [aws-destroy-validation.txt](../docs/evidence/aws-destroy-validation.txt).

## Preparacion de CD

Ver [bootstrap persistente: S3, OIDC y aprobacion](bootstrap/README.md).
Configuracion preparada, pendiente de aplicar y migrar el estado.
El laboratorio mantiene su backend actual hasta completar esa guia.

## Validacion de proveedores en Windows y Linux

Los lockfiles incluyen checksums oficiales de ambas plataformas. Si se actualiza
el proveedor, regenerarlos antes de hacer commit:

```powershell
.\.tools\terraform.exe -chdir=terraform providers lock -platform=windows_amd64 -platform=linux_amd64
.\.tools\terraform.exe -chdir=terraform/bootstrap providers lock -platform=windows_amd64 -platform=linux_amd64
```

CI ejecuta init -backend=false -lockfile=readonly y validate en Linux para ambos
roots, sin credenciales AWS. No quitar la comprobacion de checksums para evitar
un error de instalacion. Evidencia: [correccion Linux](../docs/evidence/cd-checksum-fix.txt).

## Arquitectura general

Ver [diagramas, flujo CI/CD, seguridad y ciclo de vida](../docs/architecture.md).
