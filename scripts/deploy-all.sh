#!/bin/bash
set -e

#########################################
# deploy-all.sh v.2
# script de deploy completo para proyecto cloud
# incluye: minikube, sealed-secrets, argocd, kustomize
#########################################

# directorio base del proyecto (una carpeta arriba de scripts)
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ENVIRONMENT=$1

# mostrar mensaje con timestamp
log() {
  echo "$(date '+%H:%M:%S') $1"
}

# validacion de ambiente
if [ -z "$ENVIRONMENT" ]; then
  echo "ERROR: debes especificar el ambiente"
  echo ""
  echo "uso:"
  echo "  ./deploy-all.sh <ambiente>"
  echo ""
  echo "ambientes disponibles:"
  echo "  dev         - desarrollo"
  echo "  staging     - staging/testing"
  echo "  production  - produccion"
  echo ""
  echo "ejemplo:"
  echo "  ./deploy-all.sh staging"
  exit 1
fi

echo "=========================================="
echo "DEPLOY COMPLETO: $ENVIRONMENT"
echo "=========================================="

# configuracion segun ambiente
case "$ENVIRONMENT" in
  dev)
    PROFILE="minikube-dev"
    NAMESPACE="proyecto-cloud-dev"
    ARGOCD_APP_FILE="$BASE_DIR/argocd/dev-app.yaml"
    ;;
  staging)
    PROFILE="minikube-staging"
    NAMESPACE="proyecto-cloud-staging"
    ARGOCD_APP_FILE="$BASE_DIR/argocd/staging-app.yaml"
    ;;
  production)
    PROFILE="minikube-production"
    NAMESPACE="proyecto-cloud-production"
    ARGOCD_APP_FILE="$BASE_DIR/argocd/production-app.yaml"
    ;;
  *)
    echo "ERROR: ambiente no valido"
    echo "usar: ./deploy-all.sh [dev|staging|production]"
    exit 1
    ;;
esac

# variables para secrets (pueden ser sobreescritas con variables de entorno)
export MYSQL_USER="${MYSQL_USER:-appuser}"
export MYSQL_PASSWORD="${MYSQL_PASSWORD:-devpass123}"
export MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-rootpass123}"
export JWT_SECRET="${JWT_SECRET:-GjPEfbM33noYJdEX4fymEken7svn6l81Xtnj9sX7Y7E=}"

# repositorios de docker hub
DOCKER_USER="facundo676"
FRONTEND_REPO="$DOCKER_USER/frontend-shop"
BACKEND_REPO="$DOCKER_USER/backend-shop"

log "ambiente: $ENVIRONMENT"
log "perfil minikube: $PROFILE"
log "namespace: $NAMESPACE"

#########################################
# paso 1: verificar y configurar minikube
#########################################
log ""
log "=========================================="
log "PASO 1: configurando minikube"
log "=========================================="

# verificar si el perfil existe
if ! minikube profile list 2>/dev/null | grep -q "$PROFILE"; then
  log "el perfil $PROFILE no existe, creandolo..."
  minikube start -p "$PROFILE" --cpus=4 --memory=4096 --driver=docker
  log "perfil $PROFILE creado"
else
  # verificar si esta corriendo
  if ! minikube status -p "$PROFILE" 2>/dev/null | grep -q "Running"; then
    log "iniciando minikube con perfil $PROFILE..."
    minikube start -p "$PROFILE"
  else
    log "minikube ya esta corriendo con perfil $PROFILE"
  fi
fi

# cambiar al perfil correcto
minikube profile "$PROFILE"
log "usando perfil: $PROFILE"

# verificar contexto de kubectl
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
log "contexto kubectl actual: $CURRENT_CONTEXT"

#########################################
# paso 2: instalar sealed secrets
#########################################
log ""
log "=========================================="
log "PASO 2: configurando sealed secrets"
log "=========================================="

# verificar si sealed secrets ya esta instalado
if kubectl get deployment sealed-secrets-controller -n kube-system >/dev/null 2>&1; then
  log "sealed secrets ya esta instalado"
else
  log "instalando sealed secrets controller..."
  kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.5/controller.yaml

  log "esperando a que sealed secrets este listo..."
  kubectl wait --for=condition=ready pod -l name=sealed-secrets-controller -n kube-system --timeout=120s
  log "sealed secrets instalado correctamente"
fi

# verificar si kubeseal esta instalado localmente
if ! command -v kubeseal &> /dev/null; then
  log "AVISO: kubeseal no esta instalado localmente"
  log "para crear sealed secrets, instalar con:"
  log "  wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.5/kubeseal-0.24.5-linux-amd64.tar.gz"
  log "  tar -xvzf kubeseal-0.24.5-linux-amd64.tar.gz"
  log "  sudo install -m 755 kubeseal /usr/local/bin/kubeseal"
else
  log "kubeseal esta instalado: $(kubeseal --version 2>/dev/null || echo 'version desconocida')"
fi

#########################################
# paso 3: crear namespace y secrets
#########################################
log ""
log "=========================================="
log "PASO 3: creando namespace y secrets"
log "=========================================="

# crear namespace si no existe
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  log "creando namespace $NAMESPACE..."
  kubectl create namespace "$NAMESPACE"
else
  log "namespace $NAMESPACE ya existe"
fi

# verificar si los secrets existen, si no crearlos
# nota: en produccion real, usar sealed secrets desde git
# estos secrets manuales son para desarrollo local

if ! kubectl get secret mysql-secret -n "$NAMESPACE" >/dev/null 2>&1; then
  log "creando mysql-secret..."
  kubectl create secret generic mysql-secret \
    --from-literal=root-password="$MYSQL_ROOT_PASSWORD" \
    --from-literal=username="$MYSQL_USER" \
    --from-literal=password="$MYSQL_PASSWORD" \
    -n "$NAMESPACE"
  log "mysql-secret creado"
else
  log "mysql-secret ya existe"
fi

if ! kubectl get secret app-secret -n "$NAMESPACE" >/dev/null 2>&1; then
  log "creando app-secret..."
  kubectl create secret generic app-secret \
    --from-literal=jwt-secret="$JWT_SECRET" \
    -n "$NAMESPACE"
  log "app-secret creado"
else
  log "app-secret ya existe"
fi

log "secrets configurados:"
kubectl get secrets -n "$NAMESPACE" 2>/dev/null | grep -E "mysql-secret|app-secret" || true

#########################################
# paso 4: instalar argocd
#########################################
log ""
log "=========================================="
log "PASO 4: configurando argocd"
log "=========================================="

# verificar si argocd ya esta instalado
if ! kubectl get namespace argocd >/dev/null 2>&1; then
  log "instalando argocd..."
  kubectl create namespace argocd
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  log "esperando a que argocd este listo (esto puede tardar unos minutos)..."
  kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
  log "argocd instalado correctamente"
else
  log "argocd ya esta instalado"
  # verificar que este corriendo
  if ! kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
    log "reinstalando argocd..."
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
  fi
fi

# aplicar configuracion de argocd si existe
if [ -f "$BASE_DIR/argocd-cm.yaml" ]; then
  log "aplicando configuracion de argocd..."
  kubectl apply -f "$BASE_DIR/argocd-cm.yaml" 2>/dev/null || true
fi

if [ -f "$BASE_DIR/argocd-cmd-params-cm.yaml" ]; then
  kubectl apply -f "$BASE_DIR/argocd-cmd-params-cm.yaml" 2>/dev/null || true
fi

# crear aplicacion de argocd para el ambiente
if [ -f "$ARGOCD_APP_FILE" ]; then
  log "aplicando configuracion de argocd desde: $ARGOCD_APP_FILE"
  kubectl apply -f "$ARGOCD_APP_FILE"
  log "aplicacion argocd configurada"
else
  log "AVISO: archivo $ARGOCD_APP_FILE no encontrado"
  log "creando aplicacion argocd generica..."

  cat << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: proyecto-cloud-$ENVIRONMENT
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/sudo-init-project/Infra-App-K8s
    targetRevision: HEAD
    path: overlays/$ENVIRONMENT
  destination:
    server: https://kubernetes.default.svc
    namespace: $NAMESPACE
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF
fi

#########################################
# paso 5: deploy con kustomize
#########################################
log ""
log "=========================================="
log "PASO 5: desplegando con kustomize"
log "=========================================="

OVERLAY_PATH="$BASE_DIR/overlays/$ENVIRONMENT"

if [ -d "$OVERLAY_PATH" ]; then
  log "aplicando manifiestos desde: $OVERLAY_PATH"
  kubectl apply -k "$OVERLAY_PATH" 2>&1 | grep -v "Warning.*deprecated" || true
  log "manifiestos aplicados"
else
  log "ERROR: no se encontro el overlay en $OVERLAY_PATH"
  exit 1
fi

#########################################
# paso 6: esperar a que los pods esten listos
#########################################
log ""
log "=========================================="
log "PASO 6: esperando pods"
log "=========================================="

# obtener prefijo de nombres segun ambiente
# los deployments tienen nombres como: staging-frontend-stg, staging-backend-stg, etc
ENV_PREFIX="${ENVIRONMENT}"
ENV_SUFFIX="${ENVIRONMENT:0:3}"

log "esperando frontend..."
if kubectl rollout status deployment/${ENV_PREFIX}-frontend-${ENV_SUFFIX} -n "$NAMESPACE" --timeout=180s 2>/dev/null; then
  log "frontend listo"
else
  log "AVISO: frontend tardo mucho, continuando..."
fi

log "esperando backend..."
if kubectl rollout status deployment/${ENV_PREFIX}-backend-${ENV_SUFFIX} -n "$NAMESPACE" --timeout=180s 2>/dev/null; then
  log "backend listo"
else
  log "AVISO: backend tardo mucho, continuando..."
fi

log "esperando mysql..."
if kubectl rollout status statefulset/${ENV_PREFIX}-mysql-${ENV_SUFFIX} -n "$NAMESPACE" --timeout=180s 2>/dev/null; then
  log "mysql listo"
else
  log "AVISO: mysql tardo mucho, continuando..."
fi

#########################################
# paso 7: mostrar estado final
#########################################
log ""
log "=========================================="
log "ESTADO FINAL"
log "=========================================="

echo ""
echo "pods:"
kubectl get pods -n "$NAMESPACE" 2>/dev/null || echo "error obteniendo pods"

echo ""
echo "servicios:"
kubectl get svc -n "$NAMESPACE" 2>/dev/null || echo "error obteniendo servicios"

echo ""
echo "aplicacion argocd:"
kubectl get application -n argocd 2>/dev/null | grep "$ENVIRONMENT" || echo "no se encontro aplicacion"

#########################################
# paso 8: mostrar informacion de acceso
#########################################
log ""
log "=========================================="
log "DEPLOY COMPLETADO"
log "=========================================="

# obtener password de argocd
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null)
if [ -z "$ARGOCD_PASSWORD" ]; then
  ARGOCD_PASSWORD="(no disponible, verificar instalacion)"
fi

echo ""
echo "ACCESO A ARGOCD:"
echo "  1. ejecutar: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  2. abrir: https://localhost:8080"
echo "  3. usuario: admin"
echo "  4. password: $ARGOCD_PASSWORD"
echo ""
echo "ACCESO A LA APLICACION:"
echo "  1. ejecutar: kubectl port-forward svc/${ENV_PREFIX}-frontend-service-${ENV_SUFFIX} -n $NAMESPACE 3000:80"
echo "  2. abrir: http://localhost:3000"
echo "  3. login: admin / admin"
echo ""
echo "COMANDOS UTILES:"
echo "  ver pods:     kubectl get pods -n $NAMESPACE"
echo "  ver logs:     kubectl logs -f deployment/${ENV_PREFIX}-backend-${ENV_SUFFIX} -n $NAMESPACE"
echo "  ver argocd:   kubectl get application -n argocd"
echo ""
echo "CLUSTER ACTIVO: $PROFILE"
echo ""

#########################################
# paso 9 (opcional): generar sealed secrets
#########################################
# esta seccion muestra como generar sealed secrets para git
# descomentar si se quiere generar automaticamente

# if command -v kubeseal &> /dev/null; then
#   log "generando sealed secrets para git..."
#
#   SEALED_DIR="$BASE_DIR/base/secrets"
#   mkdir -p "$SEALED_DIR"
#
#   # generar mysql sealed secret
#   kubectl create secret generic mysql-secret \
#     --from-literal=root-password="$MYSQL_ROOT_PASSWORD" \
#     --from-literal=username="$MYSQL_USER" \
#     --from-literal=password="$MYSQL_PASSWORD" \
#     --namespace="$NAMESPACE" \
#     --dry-run=client -o yaml | \
#     kubeseal --controller-namespace kube-system --controller-name sealed-secrets-controller --format yaml \
#     > "$SEALED_DIR/mysql-sealed-secret.yaml"
#
#   # generar app sealed secret
#   kubectl create secret generic app-secret \
#     --from-literal=jwt-secret="$JWT_SECRET" \
#     --namespace="$NAMESPACE" \
#     --dry-run=client -o yaml | \
#     kubeseal --controller-namespace kube-system --controller-name sealed-secrets-controller --format yaml \
#     > "$SEALED_DIR/app-sealed-secret.yaml"
#
#   log "sealed secrets generados en: $SEALED_DIR"
#   log "IMPORTANTE: hacer commit de estos archivos a git"
# fi
