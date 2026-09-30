"""Descargar herramientas Windows amd64 oficiales con comprobacion SHA-256."""
from hashlib import sha256
from pathlib import Path
import platform
import tarfile
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / '.tools'


def download(url):
    with urlopen(url, timeout=120) as response:
        return response.read()


def verified_file(url, checksum_url, filename):
    data = download(url)
    expected = download(checksum_url).decode().strip().split()[0].lower()
    if sha256(data).hexdigest() != expected:
        raise RuntimeError(f'Checksum incorrecto: {filename}')
    target = TOOLS / filename
    target.write_bytes(data)
    return target


if __name__ == '__main__':
    if platform.system() != 'Windows' or platform.machine().lower() not in ('amd64', 'x86_64'):
        raise SystemExit('Este instalador requiere Windows amd64.')
    TOOLS.mkdir(exist_ok=True)
    kind_url = 'https://github.com/kubernetes-sigs/kind/releases/download/v0.33.0/kind-windows-amd64'
    verified_file(kind_url, kind_url + '.sha256sum', 'kind.exe')
    kubectl_url = 'https://dl.k8s.io/release/v1.35.8/bin/windows/amd64/kubectl.exe'
    verified_file(kubectl_url, kubectl_url + '.sha256', 'kubectl.exe')
    helm_url = 'https://get.helm.sh/helm-v3.19.0-windows-amd64.tar.gz'
    archive = verified_file(helm_url, helm_url + '.sha256sum', 'helm.tar.gz')
    with tarfile.open(archive) as source:
        with source.extractfile('windows-amd64/helm.exe') as binary:
            (TOOLS / 'helm.exe').write_bytes(binary.read())
    print('Herramientas verificadas en', TOOLS)
