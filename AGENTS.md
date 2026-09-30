# Instrucciones del proyecto

- Comunicar y documentar en español; usar nombres de código claros en inglés.
- Mantener una API pequeña en Python con FastAPI, sin base de datos ni frontend por ahora.
- Usar `.venv` para dependencias locales y `python -m pip` para instalarlas.
- Colocar código en `app/` y pruebas en `tests/`.
- Cuando existan pruebas, ejecutarlas con `python -m pytest` desde la raíz.
- No guardar credenciales, archivos `.env`, estado de Terraform ni kubeconfig en Git.
- Actualizar README cuando cambien los pasos de instalación o ejecución.
- Documentar evidencias reales y distinguir las tareas pendientes de las verificadas.

- CI: `.github/workflows/ci.yml`; pruebas y Bandit deben pasar antes del job Docker.
- SAST local: instalar `requirements-security.txt` y ejecutar `python -m bandit -r app`.
- Imagen remota: `ghcr.io/farid259/proyecto_devops`; publicar solo en pushes a `main`.
- Conservar acciones de GitHub fijadas por SHA; usar GITHUB_TOKEN, nunca credenciales en archivos.
- Etiquetar imagen con el SHA del commit y verificar el contenedor antes de publicarla.

- DAST: ejecutar ZAP API Scan contra la API temporal del runner antes de publicar; WARN, FAIL y errores bloquean la imagen.
- Guardar reportes ZAP como artifacts incluso cuando el escaneo falle; no ignorar alertas sin justificar la regla concreta.

- Kubernetes local: cluster kind `proyecto-devops`, contexto `kind-proyecto-devops`, namespace `devops`.
- Usar `.tools/kubectl.exe --kubeconfig .local/kubeconfig --context kind-proyecto-devops`; no tocar otros clusters.
- Aplicar la API con `kubectl apply -k k8s`; Ingress local http://localhost:8080.
- Mantener imagen por digest y requests de CPU para el HPA. No incluir replicas fijas en el Deployment gestionado por HPA.
- Los parches de compatibilidad cgroups v1 y kubelet-insecure-tls son solo para el laboratorio local, no para cloud.
- No versionar `.tools/` ni `.local/`; las credenciales del cluster estan en `.local/kubeconfig`.
