# Base persistente para CD

Estado: bootstrap aplicado (9 recursos), estado vacio del laboratorio guardado
en S3 y variables de aws-lab configuradas. CD_ENABLED=false hasta probar el flujo.
OIDC desde Actions todavia no verificado. No hay EKS ni EC2 del laboratorio.
Este directorio es un root Terraform separado del laboratorio EKS.
Crea S3 privado, cifrado AES256, versionado, politica TLS y rol GitHub OIDC.
S3 tiene cargos por almacenamiento y solicitudes; no crea EKS, EC2 ni NAT.
El bucket tiene prevent_destroy y force_destroy=false. No se elimina al destruir
el laboratorio. Conservar tambien el estado LOCAL de este bootstrap, fuera de Git,
en un respaldo privado: no confundirlo con el estado remoto del laboratorio.

## Preparar una vez

Se requiere una identidad autorizada para administrar este bucket, proveedor OIDC
y rol. DevOpsLabProvision no incluye estos permisos; no ampliar el rol del CD para
que pueda administrar su propia confianza. No usar credenciales permanentes en GitHub.

Desde la raiz, PowerShell:

```powershell
$env:AWS_PROFILE = "devops"
$env:TF_VAR_account_id = aws sts get-caller-identity --query Account --output text
if ($LASTEXITCODE -ne 0) { throw 'Revisar la sesion AWS' }
.\.tools\terraform.exe -chdir=terraform/bootstrap init
.\.tools\terraform.exe -chdir=terraform/bootstrap plan "-out=bootstrap.tfplan"
# Revisar los recursos, los permisos y los cargos de S3 antes de aplicar.
.\.tools\terraform.exe -chdir=terraform/bootstrap apply bootstrap.tfplan
```

Si ya existe token.actions.githubusercontent.com en IAM, configurar
TF_VAR_existing_oidc_provider_arn con su ARN antes del plan. Se reutiliza sin
modificarlo; verificar que acepte sts.amazonaws.com como audiencia.
La confianza exige el repositorio exacto Farid259/proyecto_devops y aws-lab.
La restriccion a main y la aprobacion se configuran en el entorno GitHub:
el subject OIDC de un entorno no contiene la rama.

## Configurar GitHub antes de habilitar un workflow AWS

Settings > Environments > aws-lab:

- Required reviewers: Farid259.
- Prevent self-review: desactivado para este laboratorio individual.
- Desactivar el bypass de administradores.
- Deployment branches and tags: Selected branches and tags, solo branch main.
- Variables: AWS_ACCOUNT_ID, AWS_ROLE_ARN (output github_role_arn),
  TF_STATE_BUCKET (output state_bucket), AWS_REGION=us-east-1.

El job de CD debe declarar environment: aws-lab e id-token: write.
Aprobar en Actions > ejecucion > Review deployments > Approve and deploy.
No aprobar codigo que no revisaste: el job obtiene permisos para crear recursos
facturables. La aprobacion no elimina los recursos despues.
No ejecutar codigo de pull requests no confiables con el rol AWS.

## Migrar el estado del laboratorio

Solo despues de crear el bucket. Respaldar terraform/terraform.tfstate y su backup
fuera de Git. El estado actual del laboratorio esta vacio tras destruir EKS.
La identidad local necesita los mismos permisos S3 de lectura/escritura y bloqueo
que la politica lab-state del bootstrap; DevOpsLabProvision sola no los incluye.

```powershell
New-Item -ItemType Directory -Force .local | Out-Null
$backendText = .\.tools\terraform.exe -chdir=terraform/bootstrap output -raw backend_config
if ($LASTEXITCODE -ne 0) { throw 'No se pudo obtener el backend' }
[IO.File]::WriteAllText((Join-Path (Get-Location) '.local/lab.s3.tfbackend'), ($backendText -join "`n"))
Copy-Item terraform/backend.tf.example terraform/backend.tf
.\.tools\terraform.exe -chdir=terraform init -migrate-state "-backend-config=../.local/lab.s3.tfbackend"
.\.tools\terraform.exe -chdir=terraform state list
```

Versionar backend.tf una vez activado. No versionar el archivo .local ni estados.
Mantener el workspace default. El futuro CI usara init con la misma configuracion,
sin -migrate-state. No ejecutar apply con otro backend: podria duplicar recursos.

## Alcance pendiente

El workflow CD y su destruccion manual estan implementados en cd.yml,
pendientes de ejecutar en GitHub. La politica lab-provision solo administra el laboratorio; no permite
modificar el bucket, el proveedor OIDC ni el propio rol de CD.
Terraform incluye acceso EKS para el rol CD y la IP /32 temporal del runner.
El paso final retira esa IP usando AWS; Terraform refresca ese cambio en el
siguiente plan. Si se cancela forzosamente el job, comprobar y retirar la IP.

Referencias:
- https://developer.hashicorp.com/terraform/language/backend/s3
- https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws

## Sesion local con aws login

Si el backend S3 de Terraform no reconoce AWS_PROFILE con aws login, exportar
las credenciales temporales solo al proceso PowerShell, sin imprimirlas:

```powershell
$sessionCredentials = aws configure export-credentials --profile devops --format process | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Revisar la sesion AWS' }
$env:AWS_ACCESS_KEY_ID = $sessionCredentials.AccessKeyId
$env:AWS_SECRET_ACCESS_KEY = $sessionCredentials.SecretAccessKey
$env:AWS_SESSION_TOKEN = $sessionCredentials.SessionToken
```

Cerrar esa terminal al terminar. GitHub usa OIDC, no este procedimiento.
Si la migracion de un estado vacio no crea objeto S3, comprobar que el respaldo
no tenga recursos y usar terraform state push con ese respaldo, sin -force.
Conservar DevOpsBootstrapAdmin mientras se administra el bootstrap. Antes de
retirarla, mantener permisos de estado S3 para las operaciones locales futuras.

## Subject OIDC del repositorio

Este repositorio usa use_immutable_subject=true. La confianza AWS debe coincidir
exactamente con repo:Farid259@89980590/proyecto_devops@1394095415:environment:aws-lab.
Consultar GET /repos/Farid259/proyecto_devops/actions/oidc/customization/sub
antes de reutilizar esta configuracion en otro repositorio. No usar comodines.
Referencia: https://docs.github.com/en/rest/actions/oidc
