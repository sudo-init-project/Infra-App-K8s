# Fintexa GitOps - Infraestructura Kubernetes

**Repositorio de infraestructura GitOps** para deployment automatizado de microservicios usando **ArgoCD + Helm**.

> **Principio fundamental:** Git es la única fuente de verdad del estado del cluster.

---

### Componentes

- **GitHub Actions (CI)**: Build, test, push Docker image, update infra repo
- **ArgoCD (CD)**: Monitorea Git, sincroniza cambios al cluster
- **Helm**: Templating y gestión de manifests Kubernetes
- **Kubernetes**: Cluster donde corren los microservicios

---

## Pre-requisitos

### Software Necesario

```bash
# Verificar instalaciones
kubectl version --client
minikube version
helm version
git --version
docker --version
```

### Instalar (si falta algo)

```bash
# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# docker (si no está)
sudo apt update
sudo apt install docker.io
sudo usermod -aG docker $USER
newgrp docker
```

---

## Setup Completo desde Cero

### Paso 1: Iniciar Minikube

```bash
# Iniciar cluster con recursos adecuados
minikube start --cpus=4 --memory=8192 --driver=docker

# Verificar
minikube status
kubectl get nodes
```

### Paso 2: Crear Namespaces

```bash
# Crear namespaces para los ambientes
kubectl create namespace dev
kubectl create namespace test

# Verificar
kubectl get namespaces
```

### Paso 3: Instalar ArgoCD

```bash
# Crear namespace para ArgoCD
kubectl create namespace argocd

# Instalar ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Esperar a que todos los pods estén Running (2-3 min)
kubectl get pods -n argocd -w
# Presiona Ctrl+C cuando todos estén 1/1 Running
```

### Paso 4: Acceder a ArgoCD UI

```bash
# Obtener password inicial
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# GUARDAR ESTE PASSWORD

# Port-forward para acceder a la UI
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Abrir navegador
# URL: https://localhost:8080
# Usuario: admin
# Password: (el que obtuviste arriba)
```

### Paso 5: Clonar Repositorio de Infraestructura

```bash
mkdir -p ~/Documentos/fintexa-demo
cd ~/Documentos/fintexa-demo

# Clonar este repositorio
git clone https://github.com/Demo-Fintexa/fintexa-gitops-infra.git
cd fintexa-gitops-infra
```

### Paso 6: Desplegar Applications en ArgoCD

```bash
# Aplicar todas las ArgoCD Applications
kubectl apply -f argocd-apps/backend-dev.yaml
kubectl apply -f argocd-apps/backend-test.yaml
kubectl apply -f argocd-apps/frontend-dev.yaml
kubectl apply -f argocd-apps/frontend-test.yaml

# Verificar Applications creadas
kubectl get applications -n argocd

# Expected output:
# NAME            SYNC STATUS   HEALTH STATUS
# backend-dev     Synced        Healthy
# backend-test    Synced        Healthy
# frontend-dev    Synced        Healthy
# frontend-test   Synced        Healthy
```

### Paso 7: Verificar Pods

```bash
# Ver pods en DEV
kubectl get pods -n dev

# Expected:
# NAME                                     READY   STATUS    RESTARTS   AGE
# backend-dev-backend-xxxxx-yyyyy          1/1     Running   0          2m
# frontend-dev-frontend-xxxxx-yyyyy        1/1     Running   0          2m

# Ver pods en TEST
kubectl get pods -n test

# Expected:
# NAME                                     READY   STATUS    RESTARTS   AGE
# backend-test-backend-xxxxx-yyyyy         1/1     Running   0          2m
# backend-test-backend-xxxxx-zzzzz         1/1     Running   0          2m
# frontend-test-frontend-xxxxx-aaaaa       1/1     Running   0          2m
# frontend-test-frontend-xxxxx-bbbbb       1/1     Running   0          2m
```

---

## Estructura del Repositorio

```
fintexa-gitops-infra/
├── argocd-apps/              # ArgoCD Applications
│   ├── backend-dev.yaml      # Backend DEV application
│   ├── backend-test.yaml     # Backend TEST application
│   ├── frontend-dev.yaml     # Frontend DEV application
│   └── frontend-test.yaml    # Frontend TEST application
│
├── helm-charts/              # Helm Charts
│   ├── backend/
│   │   ├── Chart.yaml        # Metadata del chart
│   │   ├── values-dev.yaml   # Valores para DEV
│   │   ├── values-test.yaml  # Valores para TEST
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       └── service.yaml
│   │
│   └── frontend/
│       ├── Chart.yaml
│       ├── values-dev.yaml
│       ├── values-test.yaml
│       └── templates/
│           ├── deployment.yaml
│           └── service.yaml
│
└── README.md
```

---

## Flujo de Deployment

### Paso a Paso Completo

#### 1. Developer hace cambio en el código

```bash
# En repo de código (BackEnd-Shop o FrontEnd-Shop)
cd ~/Documentos/fintexa-demo/BackEnd-Shop

# Hacer cambios en el código
echo "# New feature" >> README.md

# Commit
git add .
git commit -m "feat: Add new feature"

# Crear tag (determina el ambiente de destino)
git tag v1.0-dev      # Para DEV
# o
git tag v1.0-test     # Para TEST

# Push del commit
git push origin master

# Push del tag (IMPORTANTE: por separado ya me causo muchos problemas hacerlo junto)
git push origin v1.0-dev
```

#### 2. GitHub Actions (CI) ejecuta automáticamente

El pipeline:
1. Hace build de la aplicación
2. Ejecuta tests
3. Construye imagen Docker con tag `TIMESTAMP-HASH`
4. Pushea imagen a DockerHub
5. Clona este repositorio (fintexa-gitops-infra)
6. Actualiza `helm-charts/backend/values-dev.yaml` con el nuevo tag
7. Hace commit y push al repo de infra

#### 3. ArgoCD detecta el cambio

- ArgoCD hace `git pull` cada 3 minutos
- Compara estado deseado (Git) vs estado actual (Cluster)
- Detecta que `values-dev.yaml` cambió

#### 4. ArgoCD sincroniza automáticamente

- Ejecuta `helm template` para generar manifests
- Aplica cambios al cluster con `kubectl apply`
- Kubernetes hace rolling update de los pods
- Pods viejos se terminan, pods nuevos arrancan

#### 5. Verificación

```bash
# Ver pods actualizándose
kubectl get pods -n dev -w

# Ver imagen deployada
kubectl describe pod <pod-name> -n dev | grep Image:
# Debería mostrar: facundo676/backend-shop:TIMESTAMP-HASH

# Ver logs de la aplicación
kubectl logs -n dev -l app=backend --tail=20
```

---

## Notas Finales

- Este setup es para **demo/development**
- Para **producción** se necesita:
  - Secrets management (Sealed Secrets, Vault)
  - Monitoreo
  - Logging
  - Multi-cluster support
  - RBAC policies
  - Network policies

---

**Preparado por:** Facundo Herrera
**Fecha:** Diciembre 2024 (espero conseguir el trabajo)