# Acceso al laboratorio AWS; ejecutar desde PowerShell, sin credenciales en archivos.
[CmdletBinding()]
param(
    [ValidateSet('api', 'grafana', 'prometheus')]
    [string]$Service = 'api',
    [string]$Profile = 'devops',
    [ValidateRange(1024, 65535)]
    [int]$LocalPort = 0,
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$cluster = 'proyecto-devops-lab'
$context = 'proyecto-devops-aws'
$region = 'us-east-1'
$repoApi = 'https://api.github.com/repos/Farid259/proyecto_devops'
$localDir = Join-Path $projectRoot '.local'
$kubeconfig = Join-Path $localDir 'kubeconfig-aws'
$kubectl = Join-Path $projectRoot '.tools/kubectl.exe'
$tfvars = Join-Path $projectRoot 'terraform/terraform.tfvars'
$targets = @{
    api = @{ Namespace = 'traefik'; Name = 'traefik'; Remote = 80; Local = 18080; Path = '/docs' }
    grafana = @{ Namespace = 'monitoring'; Name = 'grafana'; Remote = 3000; Local = 13000; Path = '/d/devops-api' }
    prometheus = @{ Namespace = 'monitoring'; Name = 'prometheus'; Remote = 9090; Local = 19090; Path = '/targets' }
}
$target = $targets[$Service]
if (-not $PSBoundParameters.ContainsKey('LocalPort')) { $LocalPort = $target.Local }
$awsDir = Join-Path $env:ProgramFiles 'Amazon/AWSCLIV2'
if (Test-Path (Join-Path $awsDir 'aws.exe')) { $env:Path = "$awsDir;$env:Path" }
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) { throw 'Instalar AWS CLI v2.' }
if (-not (Test-Path $kubectl)) { throw 'Falta .tools/kubectl.exe; ejecutar scripts/install_tools.py.' }

function Invoke-AwsJson {
    param([string[]]$Arguments)
    $result = & aws @Arguments --profile $Profile --region $region --output json --no-cli-pager
    if ($LASTEXITCODE -ne 0) { throw "AWS fallo. Revisar sesion con: aws login --profile $Profile" }
    return (($result -join "`n") | ConvertFrom-Json)
}

# No adivinar la cuenta ni modificar clusters de otras cuentas.
$config = [IO.File]::ReadAllText($tfvars)
$accountMatch = [regex]::Match($config, '(?m)^\s*account_id\s*=\s*"(\d{12})"')
$cidrPattern = '(?m)^(\s*admin_cidr\s*=\s*")[^"]+("[^\r\n]*)'
if (-not $accountMatch.Success -or [regex]::Matches($config, $cidrPattern).Count -ne 1) {
    throw 'Configurar account_id y admin_cidr en terraform/terraform.tfvars.'
}
$identity = Invoke-AwsJson @('sts', 'get-caller-identity')
if ($identity.Account -ne $accountMatch.Groups[1].Value) { throw 'La sesion AWS pertenece a otra cuenta.' }
$info = (Invoke-AwsJson @('eks', 'describe-cluster', '--name', $cluster)).cluster
if ($info.status -ne 'ACTIVE') { throw "Cluster no disponible: $($info.status). Esperar a que finalice CD." }
if (-not $info.resourcesVpcConfig.endpointPublicAccess) { throw 'Endpoint publico deshabilitado; no se modificara.' }
$ipText = (Invoke-RestMethod 'https://checkip.amazonaws.com' -TimeoutSec 15).Trim()
$ip = $null
if (-not [Net.IPAddress]::TryParse($ipText, [ref]$ip) -or $ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
    throw 'No se obtuvo una IPv4 valida.'
}
$cidr = "$ip/32"
$current = @($info.resourcesVpcConfig.publicAccessCidrs)
Write-Host "Cluster: $cluster; IP actual: $cidr; permitidas: $($current -join ', ')"
if ($CheckOnly) {
    Write-Host 'Solo comprobacion: no se modifico AWS, GitHub, archivos ni tuneles.'
    return
}
if (Get-NetTCPConnection -LocalPort $LocalPort -State Listen -ErrorAction SilentlyContinue) {
    throw "Puerto $LocalPort ocupado. Cerrar el tunel previo o usar -LocalPort otroPuerto."
}
# Reemplazar solo el acceso individual del laboratorio; no retirar rangos ajenos.
if ($current.Count -ne 1 -or $current[0] -notmatch '/32$') {
    throw 'Hay multiples rangos o uno amplio. Puede existir un CD activo; revisar antes de reemplazarlos.'
}

# Usar autenticacion Git existente o GH_TOKEN de la sesion. Nunca imprimirla.
$token = $env:GH_TOKEN
if (-not $token) {
    $credentialLines = "protocol=https`nhost=github.com`n`n" | git -C $projectRoot -c credential.interactive=false credential fill 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Autenticarse en GitHub mediante Git Credential Manager o configurar GH_TOKEN en la sesion.' }
    $passwordLine = $credentialLines | Where-Object { $_.StartsWith('password=') } | Select-Object -First 1
    if (-not $passwordLine) { throw 'No hay credencial GitHub disponible.' }
    $token = $passwordLine.Substring(9)
}
$headers = @{ Authorization = "Bearer $token"; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
try {
    # Evitar competir con un despliegue o destruccion activo.
    $runs = Invoke-RestMethod "$repoApi/actions/runs?status=in_progress&per_page=100" -Headers $headers
    if ($runs.total_count -gt 0) { throw 'Hay workflows en ejecucion. Esperar a que terminen antes de sincronizar el acceso.' }
    $variableUrl = "$repoApi/environments/aws-lab/variables/ADMIN_CIDR"
    $null = Invoke-RestMethod $variableUrl -Headers $headers
    if ($current[0] -ne $cidr) {
        $update = Invoke-AwsJson @('eks', 'update-cluster-config', '--name', $cluster, '--resources-vpc-config', "publicAccessCidrs=$cidr")
        $deadline = (Get-Date).AddMinutes(10)
        do {
            $status = (Invoke-AwsJson @('eks', 'describe-update', '--name', $cluster, '--update-id', $update.update.id)).update.status
            Write-Host "Actualizacion de EKS: $status"
            if ($status -eq 'Successful') { break }
            if ($status -in @('Failed', 'Cancelled')) { throw 'EKS no pudo completar el cambio de IP.' }
            if ((Get-Date) -gt $deadline) { throw 'Tiempo de espera agotado; consultar la actualizacion EKS antes de reintentar.' }
            Start-Sleep -Seconds 5
        } while ($true)
    }
    $body = @{ name = 'ADMIN_CIDR'; value = $cidr } | ConvertTo-Json
    $null = Invoke-RestMethod $variableUrl -Method Patch -Headers $headers -ContentType 'application/json' -Body $body
    if ((Invoke-RestMethod $variableUrl -Headers $headers).value -ne $cidr) { throw 'No se verifico ADMIN_CIDR en GitHub.' }
    $replacement = '${1}' + $cidr + '${2}'
    [IO.File]::WriteAllText($tfvars, [regex]::Replace($config, $cidrPattern, $replacement), [Text.UTF8Encoding]::new($false))
} catch {
    throw "No se completo la sincronizacion: $($_.Exception.Message). EKS podria haberse actualizado; revisar ADMIN_CIDR antes del siguiente CD."
} finally {
    $headers = $null; $token = $null; $credentialLines = $null; $passwordLine = $null
}
New-Item -ItemType Directory -Force $localDir | Out-Null
& aws eks update-kubeconfig --profile $Profile --region $region --name $cluster --alias $context --kubeconfig $kubeconfig --no-cli-pager
if ($LASTEXITCODE -ne 0) { throw 'No se pudo actualizar kubeconfig.' }
Write-Host "Abrir http://localhost:$LocalPort$($target.Path). Ctrl+C cierra el tunel, no elimina AWS."
& $kubectl --kubeconfig $kubeconfig --context $context --request-timeout=30s -n $target.Namespace port-forward "service/$($target.Name)" "${LocalPort}:$($target.Remote)" --address=127.0.0.1
if ($LASTEXITCODE -ne 0) { throw 'El tunel termino con error; comprobar red, IP y estado del pod.' }
