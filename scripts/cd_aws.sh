#!/usr/bin/env bash
set -euo pipefail
if [ "$LAB_ACTION" = destroy ]; then
  terraform -chdir=terraform plan -destroy -lock-timeout=5m -out=destroy.tfplan
  terraform -chdir=terraform apply -lock-timeout=5m destroy.tfplan
  test -z "$(terraform -chdir=terraform state list)"
  echo 'Estado del laboratorio vacio tras destroy. Bootstrap S3/OIDC conservado.' >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi
# Solo se permite la IPv4 del runner y la del administrador.
runner_ip=$(curl --fail --silent --show-error --retry 3 https://checkip.amazonaws.com)
export TF_VAR_runner_cidr="$runner_ip/32"
terraform -chdir=terraform plan -lock-timeout=5m -out=lab.tfplan
terraform -chdir=terraform apply -lock-timeout=5m lab.tfplan
mkdir -p .local .tools
export KUBECONFIG="$PWD/.local/kubeconfig-aws"
aws eks update-kubeconfig --name proyecto-devops-lab --alias proyecto-devops-aws --kubeconfig "$KUBECONFIG"
# Descargas oficiales verificadas con los checksums publicados.
curl -fsSL --retry 3 https://dl.k8s.io/release/v1.35.8/bin/linux/amd64/kubectl -o .tools/kubectl
curl -fsSL --retry 3 https://dl.k8s.io/release/v1.35.8/bin/linux/amd64/kubectl.sha256 -o .local/kubectl.sha256
printf '%s  .tools/kubectl\n' "$(cat .local/kubectl.sha256)" | sha256sum --check
curl -fsSL --retry 3 https://get.helm.sh/helm-v3.19.0-linux-amd64.tar.gz -o .local/helm.tar.gz
curl -fsSL --retry 3 https://get.helm.sh/helm-v3.19.0-linux-amd64.tar.gz.sha256sum -o .local/helm.sha256
printf '%s  .local/helm.tar.gz\n' "$(cut -d ' ' -f1 .local/helm.sha256)" | sha256sum --check
tar -xzf .local/helm.tar.gz -C .local linux-amd64/helm
cp .local/linux-amd64/helm .tools/helm
chmod +x .tools/kubectl .tools/helm
export PATH="$PWD/.tools:$PATH"
kubectl --context proyecto-devops-aws wait --for=condition=Ready nodes --all --timeout=5m
kubectl --context proyecto-devops-aws apply -f k8s/local/metrics-server/components.yaml
helm repo add traefik https://traefik.github.io/charts
helm upgrade --install traefik traefik/traefik --version 41.6.0 --namespace traefik --create-namespace \
  --kube-context proyecto-devops-aws -f k8s/aws/traefik-values.yaml --wait --timeout 5m
# Cambiar el digest antes de apply evita iniciar la imagen antigua del manifiesto.
python3 - <<'PYTHON'
import os,re
from pathlib import Path
p=Path('k8s/deployment.yaml')
s,n=re.subn(r'ghcr.io/farid259/proyecto_devops@sha256:[a-f0-9]{64}',os.environ['DEPLOY_IMAGE'],p.read_text())
if n != 1: raise SystemExit('No se encontro exactamente una imagen para reemplazar')
p.write_text(s)
PYTHON
kubectl --context proyecto-devops-aws apply -k k8s
kubectl --context proyecto-devops-aws -n devops rollout status deployment/api --timeout=5m
kubectl --context proyecto-devops-aws -n kube-system rollout status deployment/metrics-server --timeout=3m
kubectl --context proyecto-devops-aws -n traefik port-forward service/traefik 18080:80 --address=127.0.0.1 >.local/tunnel.log 2>&1 &
tunnel_pid=$!
trap 'kill "$tunnel_pid" 2>/dev/null || true' EXIT
for attempt in {1..30}; do
  if curl -fsS http://localhost:18080/health >.local/health.json; then break; fi
  sleep 2
done
python3 - <<'PYTHON'
import json
from urllib.request import urlopen
with urlopen('http://localhost:18080/health',timeout=10) as r:
 assert json.load(r)=={'status':'ok'}
with urlopen('http://localhost:18080/api/convert?celsius=20',timeout=10) as r:
 assert json.load(r)=={'celsius':20.0,'fahrenheit':68.0,'kelvin':293.15}
PYTHON
printf 'API AWS verificada. Imagen: `%s`. Acceso manual: k8s/aws/README.md.\n' "$DEPLOY_IMAGE" >> "$GITHUB_STEP_SUMMARY"
