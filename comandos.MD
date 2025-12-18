## 🛠️ Comandos Útiles

### ArgoCD
```bash
# Listar aplicaciones
argocd app list

# Detalles de una app
argocd app get frontend-dev

# Ver diferencias (Git vs Cluster)
argocd app diff frontend-dev

# Forzar sincronización
argocd app sync frontend-dev

# Ver logs de sincronización
argocd app logs frontend-dev
```

### Kubernetes
```bash
# Ver todos los recursos en dev
kubectl get all -n dev

# Ver pods específicos
kubectl get pods -n dev -l app=frontend

# Ver logs de frontend
kubectl logs -f -l app=frontend -n dev

# Ver logs de backend
kubectl logs -f -l app=backend -n dev

# Port-forward frontend
kubectl port-forward service/frontend-dev-service 3000:80 -n dev

# Port-forward backend
kubectl port-forward service/backend-dev-service 8080:8080 -n dev

# Describir pod (debug)
kubectl describe pod <pod-name> -n dev

# Ver eventos del namespace
kubectl get events -n dev --sort-by='.lastTimestamp'
```

### Helm (validación local)
```bash
# Validar chart
helm lint helm-charts/frontend
helm lint helm-charts/backend

# Ver qué generaría (sin instalar)
helm template test helm-charts/frontend --values helm-charts/frontend/values-dev.yaml

# Ver diferencias entre values
diff helm-charts/frontend/values-dev.yaml helm-charts/frontend/values-test.yaml
```
## Decisiones Técnicas

### ¿Por qué Helm?

- **Templating:** Variables reutilizables ({{ .Values.* }})
- **Versionado:** Clear releases (v1, v2, v3)
- **Rollback:** Fácil volver a versión anterior

### ¿Por qué 2 repositorios separados?**

**Repo Código (FrontEnd-Shop, BackEnd-Shop):**
- Cambia frecuentemente (features, bugs)
- Desarrolladores trabajan aquí

**Repo Infraestructura (fintexa-gitops-infra):**
- Cambia raramente (configs, recursos)
- DevOps/SRE trabajan aquí
- Es la "fuente de verdad" del cluster

**Beneficios:**
- Separación de responsabilidades
- Diferentes permisos (devs no tocan infra directamente)
- Auditabilidad (quién cambió qué)

### ¿Por qué ArgoCD?

**GitOps Principles:**
- Git como única fuente de verdad
- Declarativo (describes WHAT, not HOW)
- Pull model (ArgoCD lee Git, no push directo)

**Ventajas:**
- **Self-healing:** Si alguien modifica cluster manualmente, ArgoCD lo revierte
- **Prune:** Elimina recursos que ya no están en Git
- **Auditable:** Todo cambio queda en Git history
- **Rollback fácil:** `git revert` + ArgoCD sync

### ¿Por qué tags determinan ambiente?

**Patrón:**
- `v1.0-dev` → Despliega a namespace `dev`
- `v1.0-test` → Despliega a namespace `test`

**Beneficios:**
- Trazabilidad clara (qué versión en qué ambiente)
- Control explícito (no deployments accidentales)
- Versionado semántico


## 🔒 Manejo de Secretos

**Simplificación para demo:**
- Secrets en Kubernetes directamente
- NO commiteados a Git

**Crear secrets manualmente:**
```bash
# Ejemplo (NO ejecutar en demo)
kubectl create secret generic app-secret \
  --from-literal=JWT_SECRET=mi-secreto \
  -n dev
```

**En producción usaríamos:**
- Sealed Secrets (encriptar secrets en Git)
- External Secrets Operator (integración con Vault)

---

## 🎓 Para la Demo (Lunes 17:00)

### Mostrar:

1. **Arquitectura** (diagrama en papel/Excalidraw)
2. **Estructura de repos** (este README)
3. **Helm charts** (values-dev vs values-test)
4. **ArgoCD Applications** (explicar syncPolicy)
5. **Flujo completo:**
   - Tag en código → CI → Update infra → ArgoCD sync
6. **Demo en vivo:**
   - Hacer cambio en código
   - Tag v1.X-dev
   - Mostrar pipeline
   - Mostrar ArgoCD sincronizando
   - Verificar Pods actualizados

### Explicar:

- **Separación CI/CD:** CI hace build, CD (ArgoCD) hace deploy
- **GitOps:** Por qué Git es fuente de verdad
- **Pull vs Push:** ArgoCD pull de Git, no push directo a cluster
- **syncPolicy.automated:** prune + selfHeal
- **Helm templating:** {{ .Values.* }}


## 📝 Suposiciones / Simplificaciones

1. **Imágenes Docker:** Ya existen en DockerHub (`facundo676/frontend-shop`, `facundo676/backend-shop`)
2. **Base de datos:** NO incluida en demo (simplificación)
3. **Secrets:** Manejados manualmente (no en Git)
4. **Cluster:** Minikube local (no cloud)
5. **CI:** GitHub Actions (simplificado)
6. **Networking:** ClusterIP (no Ingress, acceso con port-forward)
