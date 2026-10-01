"""Verificar scraping y dashboard en el cluster indicado; cerrar los tuneles al salir."""
import argparse
import json
import os
from pathlib import Path
import shutil
import tempfile
import subprocess
import time
from urllib.request import Request, urlopen


def read(url, payload=None):
    request = Request(url, data=None if payload is None else json.dumps(payload).encode(),
                      headers={"Content-Type": "application/json"})
    with urlopen(request, timeout=10) as response:
        return json.load(response)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--kubectl", default="kubectl")
    parser.add_argument("--kubeconfig", required=True)
    parser.add_argument("--context", required=True)
    args = parser.parse_args()
    commands = [args.kubectl, "--kubeconfig", args.kubeconfig, "--context", args.context, "-n", "monitoring"]
    # Los tuneles heredan este entorno; no depender del PATH de otra terminal.
    child_env = os.environ.copy()
    if os.name == "nt" and not shutil.which("aws"):
        aws_dir = Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "Amazon" / "AWSCLIV2"
        if (aws_dir / "aws.exe").is_file():
            child_env["PATH"] = str(aws_dir) + os.pathsep + child_env.get("PATH", "")
    processes = []
    logs = []
    try:
        for service, ports in [("prometheus", "19091:9090"), ("grafana", "13001:3000")]:
            log = tempfile.TemporaryFile()
            logs.append((service, log))
            processes.append(subprocess.Popen(commands + ["port-forward", "service/" + service, ports,
                              "--address=127.0.0.1"], stdout=log, stderr=subprocess.STDOUT, env=child_env))
        deadline = time.monotonic() + 180
        error = None
        while time.monotonic() < deadline:
            for process, (service, log) in zip(processes, logs):
                if process.poll() is not None:
                    log.seek(0)
                    detail = log.read().decode("utf-8", errors="replace").strip()
                    raise RuntimeError(f"Fallo port-forward de {service}:\n{detail}")
            try:
                targets = read("http://localhost:19091/api/v1/targets")["data"]["activeTargets"]
                api = [t for t in targets if t["labels"].get("job") == "api"]
                assert api and all(t["health"] == "up" for t in api), "Scraping API pendiente"
                dashboard = read("http://localhost:13001/api/dashboards/uid/devops-api")
                assert dashboard["dashboard"]["title"] == "DevOps API"
                query = {"queries": [{"refId": "A", "datasource": {"type": "prometheus", "uid": "prometheus"},
                         "expr": 'sum(up{job="api"})', "instant": True, "range": False,
                         "intervalMs": 15000, "maxDataPoints": 100}], "from": "now-5m", "to": "now"}
                result = read("http://localhost:13001/api/ds/query", query)["results"]["A"]
                assert not result.get("error"), result.get("error")
                frames = result.get("frames", [])
                assert frames and any(any(isinstance(v, (int, float)) and v >= 1 for v in f["data"]["values"][-1]) for f in frames)
                print(json.dumps({"context": args.context, "api_targets_up": len(api),
                                  "dashboard": "DevOps API", "grafana_query": "OK"}))
                return
            except Exception as exc:
                error = exc
                time.sleep(5)
        raise RuntimeError(f"Monitoreo no listo: {error}")
    finally:
        for process in processes:
            if process.poll() is None:
                process.terminate()
        for process in processes:
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        for _, log in logs:
            log.close()


if __name__ == "__main__":
    main()
