# Fintexa GitOps - Infraestructura Kubernetes

Repositorio de infraestructura GitOps para deployment automatizado de microservicios usando ArgoCD y Helm.

**Principio fundamental:** Git es la unica fuente de verdad del estado del cluster.

---

## Tabla de Contenidos

1. [Arquitectura](#arquitectura)
2. [Pre-requisitos](#pre-requisitos)
3. [Setup Completo desde Cero](#setup-completo-desde-cero)
4. [Estructura del Repositorio](#estructura-del-repositorio)
5. [Flujo de Deployment](#flujo-de-deployment)
6. [Como Probar un Cambio](#como-probar-un-cambio)
7. [Comandos Utiles](#comandos-utiles)
8. [Troubleshooting](#troubleshooting)
9. [Suposiciones y Simplificaciones](#suposiciones-y-simplificaciones)
10. [Repositorios Relacionados](#repositorios-relacionados)

---

## Arquitectura

### Flujo CI/CD Completo

El diagrama detallado de arquitectura esta disponible en el archivo `arquitectura.excalidraw`.

### Componentes

- **GitHub Actions (CI)**: Build, test, push Docker image, update infra repo
- **ArgoCD (CD)**: Monitorea Git, sincroniza cambios al cluster
- **Helm**: Templating y gestion de manifests Kubernetes
- **Kubernetes**: Cluster donde corren los microservicios

### Separacion de Responsabilidades

**CI (GitHub Actions)**:
1. Ejecuta tests
2. Construye Docker image con tag unico (TIMESTAMP-HASH)
3. Pushea imagen a DockerHub
4. Actualiza este repositorio (values.yaml)
5. NO toca el cluster directamente

**CD (ArgoCD)**:
1. Hace git pull cada 3 minutos
2. Detecta cambios en values.yaml
3. Renderiza templates con Helm
4. Aplica cambios al cluster
5. Es el UNICO que hace kubectl apply

**Principio clave**: CI actualiza Git, CD actualiza Cluster. Esta separacion asegura que Git sea la unica fuente de verdad.

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

# Esperar a que todos los pods esten Running (2-3 min)
kubectl get pods -n argocd -w
# Presiona Ctrl+C cuando todos esten 1/1 Running
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
├── arquitectura.excalidraw   # Diagrama de arquitectura
└── README.md
```

---

## Flujo de Deployment

### Descripcion General

El flujo completo desde codigo hasta cluster tarda aproximadamente 6-10 minutos y sigue estos pasos:

### Paso a Paso Detallado

#### 1. Developer hace cambio en el codigo

```bash
# En repo de codigo (BackEnd-Shop o FrontEnd-Shop)
cd ~/Documentos/fintexa-demo/BackEnd-Shop

# Hacer cambios en el codigo
vim src/main/java/...

# Commit
git add .
git commit -m "feat: Add new feature"

# Crear tag (determina el ambiente de destino)
git tag v1.0-dev      # Para DEV
# o
git tag v1.0-test     # Para TEST

# Push del commit PRIMERO
git push origin master

# Push del tag DESPUES (SEPARADO)
git push origin v1.0-dev
```

**IMPORTANTE**: El tag debe pushearse por separado del commit para que GitHub Actions lo detecte correctamente.

#### 2. GitHub Actions (CI) ejecuta automaticamente

El pipeline detecta el tag y ejecuta:

1. **Build**: Compila la aplicacion (Maven o npm)
2. **Test**: Ejecuta tests unitarios
3. **Docker Build**: Construye imagen con tag unico `TIMESTAMP-HASH`
   - Ejemplo: `20251220-123456-abc1234`
4. **Docker Push**: Sube imagen a DockerHub
5. **Update Infrastructure**:
   - Clona este repositorio
   - Actualiza `helm-charts/backend/values-dev.yaml`
   - Cambia `image.tag: "20251220-123456-abc1234"`
   - Hace commit y push

**Duracion**: 3-5 minutos

#### 3. ArgoCD detecta el cambio

- ArgoCD hace `git pull` cada 3 minutos
- Compara estado deseado (Git) vs estado actual (Cluster)
- Detecta que `values-dev.yaml` cambio

**Duracion**: 1-3 minutos (depende del timing del poll)

#### 4. ArgoCD sincroniza automaticamente

1. Ejecuta `helm template` para generar manifests
2. Compara manifests con estado del cluster
3. Detecta diferencia (OutOfSync)
4. Aplica cambios con `kubectl apply` (porque automated sync esta habilitado)
5. Kubernetes hace rolling update de los pods:
   - Crea pod nuevo con imagen nueva
   - Espera a que este Ready
   - Termina pod viejo
6. ArgoCD valida health de los nuevos pods
7. Marca la Application como Synced y Healthy

**Duracion**: 1-2 minutos

### Logica de Ambientes

Los tags determinan el ambiente de destino:

```bash
# Tags con sufijo -dev -> despliegan a namespace dev
git tag v1.0-dev
git tag v1.1-dev
git tag v2.0-dev

# Tags con sufijo -test -> despliegan a namespace test
git tag v1.0-test
git tag v1.1-test
git tag v2.0-test
```

### Diferencias entre DEV y TEST

| Caracteristica | DEV | TEST |
|---------------|-----|------|
| **Replicas Backend** | 1 | 2 |
| **Replicas Frontend** | 1 | 2 |
| **CPU Request** | 50m / 200m | 100m / 200m |
| **Memory Request** | 64Mi / 256Mi | 128Mi / 256Mi |
| **Namespace** | `dev` | `test` |

---

## Como Probar un Cambio

Esta seccion describe como hacer un deployment de prueba end-to-end para verificar que el flujo GitOps funciona correctamente.

### Opcion 1: Deployment Manual (Paso a Paso)

#### Backend a DEV

```bash
# 1. Ir al repositorio de codigo
cd ~/Documentos/fintexa-demo/BackEnd-Shop

# 2. Hacer un cambio visible
echo "# Test deployment $(date)" >> README.md

# 3. Commit
git add README.md
git commit -m "test: Deployment to dev - $(date +%Y%m%d-%H%M%S)"

# 4. Crear y pushear tag
git tag v1.5-dev
git push origin master
git push origin v1.5-dev

# 5. Anotar la hora
echo "Tag pusheado a las: $(date +%H:%M:%S)"

# 6. Monitorear GitHub Actions
# Abrir: https://github.com/Demo-Fintexa/BackEnd-Shop/actions
# Esperar 3-5 minutos a que el workflow termine (checkmark verde)

# 7. Verificar que el repo de infra se actualizo
cd ~/Documentos/fintexa-demo/fintexa-gitops-infra
git pull
cat helm-charts/backend/values-dev.yaml | grep tag:
# Deberia mostrar: tag: "YYYYMMDD-HHMMSS-HASH"

# 8. Monitorear ArgoCD
kubectl get application backend-dev -n argocd -w
# Esperar a ver: Synced + Healthy
# Ctrl+C para salir

# 9. Ver pods actualizandose
kubectl get pods -n dev -w
# Ctrl+C cuando se estabilice

# 10. Verificar la imagen deployada
kubectl describe pod -n dev -l app=backend | grep Image:
# Deberia mostrar: facundo676/backend-shop:YYYYMMDD-HHMMSS-HASH

# 11. Verificar logs
kubectl logs -n dev -l app=backend --tail=20
# Deberia mostrar: "Started ExamenfinalApplication in XX seconds"
```

#### Frontend a TEST

```bash
# 1. Ir al repositorio
cd ~/Documentos/fintexa-demo/FrontEnd-Shop

# 2. Hacer cambio
echo "# Test deployment $(date)" >> README.md
git add README.md
git commit -m "test: Frontend to test"

# 3. Tag y push
git tag v1.5-test
git push origin master
git push origin v1.5-test

# 4-11. Seguir mismos pasos que Backend (cambiar dev por test)
```

### Opcion 2: Script Automatizado

```bash
# Usar el script de prueba
chmod +x test-deployment.sh
./test-deployment.sh

# Seleccionar:
# 1) Backend a DEV
# 2) Backend a TEST
# 3) Frontend a DEV
# 4) Frontend a TEST

# El script hace todo automaticamente y muestra el progreso
```

### Verificacion Rapida Post-Deployment

```bash
# Ejecutar este bloque para verificar que el deployment funciono:

cd ~/Documentos/fintexa-demo/fintexa-gitops-infra
git pull -q

echo "========================================"
echo "TAG EN VALUES:"
echo "========================================"
cat helm-charts/backend/values-test.yaml | grep tag:

echo ""
echo "========================================"
echo "IMAGEN EN PODS:"
echo "========================================"
kubectl describe pod -n test -l app=backend | grep "Image:" | head -2

echo ""
echo "========================================"
echo "ESTADO DE PODS:"
echo "========================================"
kubectl get pods -n test -l app=backend
```

**Resultado esperado**:
- Tag en values.yaml: `YYYYMMDD-HHMMSS-HASH`
- Imagen en pods: `facundo676/backend-shop:YYYYMMDD-HHMMSS-HASH`
- Pods: `1/1 Running`

### Tiempos Esperados

| Etapa | Tiempo |
|-------|--------|
| Push tag -> Workflow start | 10-30 segundos |
| GitHub Actions workflow | 3-5 minutos |
| ArgoCD detecta cambio | 1-3 minutos |
| Rolling update completo | 1-2 minutos |
| **Total end-to-end** | **6-10 minutos** |

---

## Comandos Utiles

### Ver Estado General

```bash
# Ver todas las ArgoCD Applications
kubectl get applications -n argocd

# Ver pods en todos los namespaces
kubectl get pods -A | grep -E "(dev|test)"

# Ver services
kubectl get svc -n dev
kubectl get svc -n test
```

### ArgoCD Commands

```bash
# Ver status de una application
kubectl describe application backend-dev -n argocd

# Forzar sincronizacion
kubectl patch application backend-dev -n argocd \
  --type merge -p '{"operation":{"sync":{"prune":true}}}'

# Ver logs de ArgoCD
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50
```

### Helm Commands

```bash
# Renderizar templates localmente
helm template backend-dev ./helm-charts/backend \
  --namespace dev \
  --values ./helm-charts/backend/values-dev.yaml

# Validar chart
helm lint ./helm-charts/backend

# Ver diferencias entre dev y test
diff <(helm template backend-dev ./helm-charts/backend -f helm-charts/backend/values-dev.yaml) \
     <(helm template backend-test ./helm-charts/backend -f helm-charts/backend/values-test.yaml)
```

### Debugging

```bash
# Ver logs de un pod
kubectl logs <pod-name> -n dev

# Ver logs del pod anterior (si crasheo)
kubectl logs <pod-name> -n dev --previous

# Ver logs en tiempo real
kubectl logs <pod-name> -n dev -f

# Ver eventos del namespace
kubectl get events -n dev --sort-by='.lastTimestamp' | tail -20

# Describir un pod
kubectl describe pod <pod-name> -n dev
```

### Port-Forwarding para Testing

```bash
# Backend DEV
kubectl port-forward svc/backend-dev-service 8080:8080 -n dev &

# Frontend DEV
kubectl port-forward svc/frontend-dev-service 3000:80 -n dev &

# Probar
curl http://localhost:8080/actuator/health
curl http://localhost:3000

# Matar port-forwards
pkill -f "port-forward"
```

---

## Troubleshooting

### Metodologia de Debugging

Orden de investigacion:

1. **ArgoCD Application**
   ```bash
   kubectl get application backend-dev -n argocd
   ```

2. **Kubernetes Resources**
   ```bash
   kubectl get deployments,pods,svc -n dev
   ```

3. **Pod Details**
   ```bash
   kubectl describe pod <pod-name> -n dev
   ```

4. **Application Logs**
   ```bash
   kubectl logs <pod-name> -n dev
   ```

5. **Events**
   ```bash
   kubectl get events -n dev --sort-by='.lastTimestamp'
   ```

### Problemas Comunes

#### 1. Pods en CrashLoopBackOff

**Sintomas:**
```bash
kubectl get pods -n dev
# NAME                     READY   STATUS             RESTARTS
# backend-dev-backend-xxx  0/1     CrashLoopBackOff   5
```

**Diagnostico:**
```bash
# Ver logs del pod crasheado
kubectl logs backend-dev-backend-xxx -n dev --previous

# Ver eventos
kubectl describe pod backend-dev-backend-xxx -n dev | grep -A 10 "Events"
```

**Causas comunes:**
1. Imagen no existe en DockerHub
2. Error en la aplicacion (exception, missing dependency)
3. Health checks muy agresivos (initialDelaySeconds muy bajo)

**Soluciones:**
1. Verificar tag en values.yaml y que exista en DockerHub
2. Fix codigo, rebuild imagen
3. Aumentar initialDelaySeconds o desactivar probes temporalmente

#### 2. Application OutOfSync

**Sintomas:**
```bash
kubectl get application backend-dev -n argocd
# NAME          SYNC STATUS   HEALTH STATUS
# backend-dev   OutOfSync     Healthy
```

**Causas:**
- Alguien hizo `kubectl edit` manualmente
- Git cambio pero ArgoCD no ha sincronizado

**Solucion:**
```bash
# Si selfHeal=true, ArgoCD lo arreglara solo
# Si no, sync manual:
kubectl patch application backend-dev -n argocd \
  --type merge -p '{"operation":{"sync":{"prune":true}}}'
```

#### 3. Imagen No Se Actualiza

**Sintomas:**
- values.yaml tiene tag nuevo
- Pods usan tag viejo

**Causa:**
```yaml
imagePullPolicy: IfNotPresent
```

**Solucion:**
Cambiar a `Always` en values.yaml:
```yaml
image:
  pullPolicy: Always
```

#### 4. GitHub Actions Workflow Falla

**Diagnostico:**
```
GitHub Repo -> Actions -> Click en workflow -> Ver logs
```

**Errores comunes:**
- Tests fallan: Fix tests, commit, re-tag
- Docker push falla: Verificar DOCKER_PASSWORD secret
- Update infra falla: Verificar INFRA_TOKEN secret y permisos

---

## Suposiciones y Simplificaciones

Este proyecto es una demo tecnica. Para produccion se necesitarian las siguientes mejoras:

### 1. Base de Datos

**Implementacion actual:**
- Backend usa H2 in-memory database
- Datos se pierden al reiniciar pods

**Para produccion:**
- MySQL o PostgreSQL con StatefulSet
- Persistent Volumes para data
- Backups automatizados

### 2. Secrets Management

**Implementacion actual:**
- No hay secrets sensibles (H2 no requiere password)
- Variables de entorno en ConfigMaps

**Para produccion:**
- Sealed Secrets o External Secrets Operator
- Secrets almacenados en Vault
- Rotacion automatica de secrets
- No commitear secrets a Git

### 3. Health Checks

**Implementacion actual:**
- Health checks desactivados temporalmente
- Backend tarda 90+ segundos en arrancar

**Para produccion:**
- Startup probes (K8s 1.16+)
- Liveness y readiness con delays apropiados
- Optimizar tiempo de startup de aplicaciones

### 4. Monitoring y Logging

**Implementacion actual:**
- Solo logs via `kubectl logs`
- No hay metricas ni alertas

**Para produccion:**
- Prometheus para metricas
- Grafana para dashboards
- ELK Stack o Loki para logs centralizados
- Alertmanager para alertas

### 5. Security

**Implementacion actual:**
- ArgoCD con password default
- No hay RBAC granular
- No hay NetworkPolicies

**Para produccion:**
- SSO/SAML para ArgoCD
- RBAC por equipo/aplicacion
- NetworkPolicies para limitar trafico
- PodSecurityPolicies
- Image scanning en CI

### 6. High Availability

**Implementacion actual:**
- Minikube (single node)
- 1-2 replicas por servicio

**Para produccion:**
- Cluster multi-node (3+ nodes)
- 3+ replicas con anti-affinity
- Multiple availability zones
- ArgoCD HA (multiple replicas)

### 7. Disaster Recovery

**Implementacion actual:**
- Git es el backup
- No hay plan de DR documentado

**Para produccion:**
- Backups automaticos de:
  - Databases
  - ArgoCD config
  - Secrets
- Plan de DR documentado y testeado
- RTO/RPO definidos

### 8. CI/CD

**Implementacion actual:**
- Tags manuales determinan ambiente
- No hay gating entre ambientes

**Para produccion:**
- Automated testing en cada PR
- Gating/Approvals para TEST/PROD
- Rollback automatico en caso de fallo
- Blue/Green o Canary deployments
- Performance testing automatizado

### 9. Multi-Tenancy

**Implementacion actual:**
- Single cluster, multiple namespaces

**Para produccion:**
- Considerar clusters separados por ambiente
- O multi-tenancy robusto con:
  - Resource Quotas
  - LimitRanges
  - NetworkPolicies estrictas

### 10. Image Tags

**Implementacion actual:**
- Tags basados en timestamp-hash
- No hay versionado semantico

**Para produccion:**
- Semantic versioning (v1.2.3)
- Tags inmutables
- Image signing (cosign)
- Vulnerability scanning

### Decisiones Tecnicas Justificadas

#### Por que separar repositorios de codigo e infraestructura?

1. **Separacion de concerns**: Developers se enfocan en codigo, Platform team en infra
2. **Permisos granulares**: Diferentes equipos, diferentes accesos
3. **Ciclo de vida diferente**: Codigo cambia frecuentemente, infra es mas estable
4. **Auditabilidad**: Cada cambio de infra tiene commit con autor y timestamp

#### Por que Helm y no manifests planos?

1. **DRY**: Un template, multiples ambientes
2. **Packaging**: Distribuir aplicaciones como charts
3. **Rollback**: `helm rollback` vuelve a version anterior
4. **Community**: Miles de charts pre-hechos

#### Por que ArgoCD y no Flux?

1. **UI intuitiva**: Visualizacion del estado del cluster
2. **Helm support**: Primera clase, bien integrado
3. **RBAC granular**: Control fino de accesos
4. **Adopcion**: CNCF graduated project, ampliamente usado

#### Por que tags y no branches?

1. **Explicito**: `v1.0-dev` es claro, no ambiguo
2. **Auditable**: Git history muestra que se deployo cuando
3. **Rollback facil**: Re-push tag viejo o revert commit
4. **No merge hell**: Evita problemas con branches

---

## Repositorios Relacionados

| Repositorio | Descripcion | URL |
|-------------|-------------|-----|
| **BackEnd-Shop** | Codigo Spring Boot | https://github.com/Demo-Fintexa/BackEnd-Shop |
| **FrontEnd-Shop** | Codigo React | https://github.com/Demo-Fintexa/FrontEnd-Shop |
| **fintexa-gitops-infra** | Infraestructura GitOps (este repo) | https://github.com/Demo-Fintexa/fintexa-gitops-infra |

---

**Preparado por:** Facundo Herrera con mucho <3
**Fecha:** Diciembre 2024