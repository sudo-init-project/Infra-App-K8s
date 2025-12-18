# Fintexa GitOps - Infraestructura para la demo tecnica

Repositorio de infraestructura basado en GitOps para despliegue automatizado de microservicios usando ArgoCD + Helm que es lo que pidieron.

---

El principio es que git sea la unica fuente de verdad del estado del cluster

---

## La Estructura del repo es la siguiente
```
fintexa-gitops-infra/
├── helm-charts/              # Helm Charts por microservicio
│   ├── frontend/
│   │   ├── Chart.yaml
│   │   ├── values-dev.yaml    # Valores para ambiente dev
│   │   ├── values-test.yaml   # Valores para ambiente test
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       └── NOTES.txt
│   └── backend/
│       ├── Chart.yaml
│       ├── values-dev.yaml
│       ├── values-test.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── service.yaml
│           └── NOTES.txt
├── argocd-apps/              # Aplicaciones ArgoCD
│   ├── frontend-dev.yaml
│   ├── frontend-test.yaml
│   ├── backend-dev.yaml
│   └── backend-test.yaml
└── README.md
```

---

## Flujo de Despliegue Completo

### 1.Desarrollador hace cambio en el codigo
```bash
# En repo FrontEnd-Shop o BackEnd-Shop
git add .
git commit -m "Update: añadimos gatitos"

# Tag determina ambiente de destino
git tag v1.0-dev      # Despliega a namespace dev
# o
git tag v1.0-test     # Despliega a namespace test

git push v1.0-dev
```

### 2.Pipeline CI (Aca entra GitHub Actions)

El pipeline automaticamente:
1. Hace build de la imagen Docker
2. Push a DockerHub con tag `v1.0-dev`
3. **Actualiza este repositorio** (fintexa-gitops-infra)
   - Modifica `helm-charts/frontend/values-dev.yaml`
   - Cambia `image.tag: "v1.0-dev"`
4. Commit automatico al repo de infra

### 3.ArgoCD detecta el cambio

- Hace `git pull` cada 3 minutos
- Compara estado deseado (Git) vs estado actual (Cluster)
- Detecta que `values-dev.yaml` cambió

### 4.ArgoCD sincroniza automáticamente

- Ejecuta `helm upgrade` con nuevos valores
- Kubernetes crea nuevos Pods con imagen `v1.0-dev`
- Rolling update automático

### 5️.Verificación
```bash
kubectl get pods -n dev
# Debería mostrar Pods con imagen v1.0-dev

kubectl describe pod <pod-name> -n dev | grep Image:
# Image: facundo676/frontend-shop:v1.0-dev
```

---

## Para que funcione este es el setup completo

### Prerequisitos
```bash
# 1. Minikube corriendo
minikube start --cpus=4 --memory=8192

# 2. Crear namespaces
kubectl create namespace dev
kubectl create namespace test

# 3. Instalar ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

```

### Acceder a ArgoCD UI
```bash
# Obtener password inicial
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo

# Port-forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Abrir navegador
# URL: https://localhost:8080
# Usuario: admin
# Password: (el que sacaste de arriba)
```

### Desplegar Aplicaciones
```bash
# Aplicar todas las aplicaciones ArgoCD
kubectl apply -f argocd-apps/frontend-dev.yaml
kubectl apply -f argocd-apps/frontend-test.yaml
kubectl apply -f argocd-apps/backend-dev.yaml
kubectl apply -f argocd-apps/backend-test.yaml

# Ver aplicaciones creadas
kubectl get applications -n argocd

# Ver en CLI
argocd app list
```

---

## Como Probar un Cambio (Demo)

### Escenario: Actualizar frontend en DEV
```bash
# 1. En repo FrontEnd-Shop
cd ~/FrontEnd-Shop
echo "Cambio de prueba" >> README.md
git add .
git commit -m "Test: cambio para demo"
git tag v1.1-dev
git push origin v1.1-dev

# 2. Ver pipeline corriendo
# GitHub → FrontEnd-Shop → Actions tab
# Esperar que termine (1-2 min)

# 3. Verificar que actualizó repo de infra
cd ~/fintexa-gitops-infra
git pull
cat helm-charts/frontend/values-dev.yaml | grep tag:
# Debería mostrar: tag: "v1.1-dev"

# 4. Ver ArgoCD sincronizando
# https://localhost:8080 → frontend-dev
# O en CLI:
argocd app get frontend-dev

# 5. Verificar Pods actualizados
kubectl get pods -n dev
kubectl describe pod <pod-name> -n dev | grep Image:
# Debería mostrar: facundo676/frontend-shop:v1.1-dev

# 6. Probar aplicación
kubectl port-forward service/frontend-dev-service 3000:80 -n dev
# Abrir: http://localhost:3000
```

---


## 🔗 Repositorios

| Repo | URL | Propósito |
|------|-----|-----------|
| **Frontend** | https://github.com/Demo-Fintexa/FrontEnd-Shop | Código React |
| **Backend** | https://github.com/Demo-Fintexa/BackEnd-Shop | Código Spring Boot |
| **Infraestructura** | https://github.com/Demo-Fintexa/fintexa-gitops-infra | Helm + ArgoCD (este repo) |

---

**Preparado por:** Facundo
**Para:** Fintexa - Prueba Técnica DevOps Engineer
**Fecha:** Diciembre 2024
EOF