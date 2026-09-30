$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$toolsDir = Join-Path $projectRoot '.tools'
$localDir = Join-Path $projectRoot '.local'
$kubeconfig = Join-Path $localDir 'kubeconfig'
$kind = Join-Path $toolsDir 'kind.exe'
$kubectl = Join-Path $toolsDir 'kubectl.exe'
$helm = Join-Path $toolsDir 'helm.exe'
foreach ($tool in @($kind, $kubectl, $helm)) {
    if (-not (Test-Path -LiteralPath $tool)) { throw 'Ejecutar primero python scripts/install_tools.py' }
}
New-Item -ItemType Directory -Force $localDir | Out-Null
$env:HELM_CACHE_HOME = Join-Path $localDir 'helm/cache'
$env:HELM_CONFIG_HOME = Join-Path $localDir 'helm/config'
$env:HELM_DATA_HOME = Join-Path $localDir 'helm/data'

function Invoke-Checked {
    param([string]$Command, [string[]]$Arguments)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Fallo: $Command $Arguments" }
}

Invoke-Checked 'docker' @('info', '--format', '{{.OSType}}')
$clusters = & $kind get clusters
if ($LASTEXITCODE -ne 0) { throw 'No se pudo consultar kind.' }
if ($clusters -notcontains 'proyecto-devops') {
    Invoke-Checked $kind @('create','cluster','--name','proyecto-devops','--config', (Join-Path $projectRoot 'k8s/local/kind.yaml'), '--kubeconfig',$kubeconfig,'--wait','180s')
} else {
    Invoke-Checked $kind @('export','kubeconfig','--name','proyecto-devops','--kubeconfig',$kubeconfig)
}
$kargs = @('--kubeconfig',$kubeconfig,'--context','kind-proyecto-devops')
Invoke-Checked $kubectl ($kargs + @('apply','-k',(Join-Path $projectRoot 'k8s/local/metrics-server')))
Invoke-Checked $kubectl ($kargs + @('-n','kube-system','rollout','status','deployment/metrics-server','--timeout=180s'))
Invoke-Checked $helm @('repo','add','traefik','https://traefik.github.io/charts','--force-update')
Invoke-Checked $helm @('repo','update','traefik')
Invoke-Checked $helm @('upgrade','--install','traefik','traefik/traefik','--version','41.6.0','--namespace','traefik','--create-namespace','--kubeconfig',$kubeconfig,'--kube-context','kind-proyecto-devops','--values',(Join-Path $projectRoot 'k8s/local/traefik-values.yaml'),'--wait','--timeout','180s')
Invoke-Checked $kubectl ($kargs + @('apply','-k',(Join-Path $projectRoot 'k8s')))
Invoke-Checked $kubectl ($kargs + @('-n','devops','rollout','status','deployment/api','--timeout=180s'))
Invoke-Checked $kubectl ($kargs + @('-n','devops','get','pods,svc,ingress,hpa'))
Write-Host 'API: http://localhost:8080/docs'
Write-Host "Kubeconfig local: $kubeconfig (no modifica el contexto global)."
