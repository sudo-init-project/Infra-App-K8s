#!/bin/bash
set -e

#########################################
# Script para desplegar ambiente completo
# CON ARGOCD Y SEALED SECRETS
#########################################

ENVIRONMENT=${1:-staging}
CPUS=${2:-4}
MEMORY=${3:-8192}

# Variables de entorno por defecto
export MYSQL_USER="${MYSQL_USER:-appuser}"
export MYSQL_PASSWORD="${MYSQL_PASSWORD:-devpass123}"
export MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-rootpass123}"
export JWT_SECRET="${JWT_SECRET:-GjPEfbM33noYJdEX4fymEken7svn6l81Xtnj9sX7Y7E=}"

# Cargar variables desde .env si existe
if [ -f ".env" ]; then
  echo "🔐 Cargando variables desde .env"
  source .env
fi

clear
echo "🚀 ============================================"
echo "🚀 DESPLEGANDO AMBIENTE: $ENVIRONMENT"
echo "🚀 ============================================"
date

#########################################
# Validar ambiente
#########################################
case "$ENVIRONMENT" in
  dev|staging|production)
    echo "🟢 Ambiente de trabajo: $ENVIRONMENT"
    PROFILE="minikube-$ENVIRONMENT"
    NAMESPACE="proyecto-cloud-$ENVIRONMENT"
    CONTEXT="$PROFILE"
    ;;
  *)
    echo "❌ ENVIRONMENT debe ser uno de: dev, staging, production"
    echo "❌ Uso: $0 [dev|staging|production] [cpus] [memory]"
    exit 1
    ;;
esac

#########################################
# Verificar dependencias
#########################################
echo "🔍 Verificando dependencias..."
for cmd in minikube kubectl; do
  if ! command -v $cmd &> /dev/null; then
    echo "❌ $cmd no está instalado"
    exit 1
  fi
done
echo "✅ Todas las dependencias están instaladas"
echo ""

#########################################
# Iniciar Minikube
#########################################
echo "🚀 Iniciando Minikube con perfil $PROFILE..."

if minikube status -p "$PROFILE" | grep -q "Running"; then
  echo "🟢 Minikube ya está corriendo en el perfil $PROFILE"
else
  echo "🟢 Iniciando Minikube..."
  minikube start -p "$PROFILE" \
    --cpus="$CPUS" \
    --memory="$MEMORY" \
    --addons=metrics-server,dashboard,ingress || {
    echo "❌ Error iniciando Minikube. Intentando con recursos reducidos..."
    minikube start -p "$PROFILE" \
      --cpus=2 \
      --memory=4096 \
      --addons=metrics-server,dashboard,ingress
  }
fi
echo ""

#########################################
# Configurar contexto
#########################################
echo "🔧 Configurando contexto Kubernetes..."
if kubectl config get-contexts "$CONTEXT" >/dev/null 2>&1; then
  echo "🟢 Contexto '$CONTEXT' ya existe"
else
  echo "🟢 Creando contexto '$CONTEXT'..."
  kubectl config set-context "$CONTEXT" \
    --cluster="$PROFILE" \
    --user="$PROFILE" \
    --namespace="$NAMESPACE"
fi

kubectl config use-context "$CONTEXT"
echo "✅ Contexto actual: $(kubectl config current-context)"
echo ""

#########################################
# Instalar ArgoCD
#########################################
echo "🚀 Instalando ArgoCD..."
ARGOCD_NAMESPACE="argocd"

if kubectl get namespace "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
  echo "🟢 Namespace '$ARGOCD_NAMESPACE' ya existe"
else
  echo "🟢 Creando namespace '$ARGOCD_NAMESPACE'..."
  kubectl create namespace "$ARGOCD_NAMESPACE"
fi

if kubectl get deployment argocd-server -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
  echo "🟢 ArgoCD ya está instalado"
else
  echo "🟢 Instalando ArgoCD..."
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  
  echo "⏳ Esperando a que ArgoCD esté listo..."
  kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
fi
echo ""

#########################################
# Generar Sealed Secrets para este cluster
#########################################
echo "🔐 Generando Sealed Secrets para el cluster actual..."

# Ejecutar script de generación de sealed secrets
if [ -f "scripts/generate-sealed-secrets.sh" ]; then
  chmod +x scripts/generate-sealed-secrets.sh
  ./scripts/generate-sealed-secrets.sh "$ENVIRONMENT"
else
  echo "❌ No se encontró scripts/generate-sealed-secrets.sh"
  echo "💡 Asegúrate de que el script esté en la ubicación correcta"
  exit 1
fi
echo ""

#########################################
# Commitear sealed secrets a Git
#########################################
echo "📝 Commiteando Sealed Secrets a Git..."

if [ -d ".git" ]; then
  # Verificar si hay cambios
  if ! git diff --quiet overlays/$ENVIRONMENT/ 2>/dev/null; then
    echo "📋 Cambios detectados en overlays/$ENVIRONMENT/"
    
    # Mostrar archivos modificados
    echo "📁 Archivos modificados:"
    git status --porcelain overlays/$ENVIRONMENT/ || true
    
    # Hacer commit
    git add overlays/$ENVIRONMENT/
    git commit -m "🔐 Add sealed secrets for $ENVIRONMENT environment

- Generated sealed secrets for current cluster
- Secrets are encrypted and safe to store in Git
- Environment: $ENVIRONMENT
- Timestamp: $(date)" || {
      echo "⚠️ Error al hacer commit, pero continuamos..."
    }
    
    echo "📤 Pusheando cambios..."
    git push || {
      echo "⚠️ Error al pushear, pero continuamos..."
    }
    
    echo "✅ Sealed Secrets commiteados y pusheados"
  else
    echo "ℹ️ No hay cambios nuevos en sealed secrets"
  fi
else
  echo "⚠️ No es un repositorio Git, saltando commit"
fi
echo ""

#########################################
# Aplicar ArgoCD Application
#########################################
echo "🎯 Desplegando aplicación ArgoCD para $ENVIRONMENT..."

# Eliminar aplicación existente si hay conflictos
kubectl delete application "proyecto-cloud-$ENVIRONMENT" -n argocd --ignore-not-found=true
sleep 5

# Aplicar nueva aplicación
if [ -f "argocd/${ENVIRONMENT}-app.yaml" ]; then
  kubectl apply -f "argocd/${ENVIRONMENT}-app.yaml"
  echo "✅ Aplicación ArgoCD creada"
else
  echo "⚠️ No se encontró argocd/${ENVIRONMENT}-app.yaml"
  echo "💡 Creando aplicación ArgoCD genérica..."
  
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
    repoURL: $(git remote get-url origin 2>/dev/null || echo "https://github.com/sudo-init-project/Infra-App-K8s")
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
    - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
fi

echo "⏳ Esperando sincronización de ArgoCD..."
sleep 15

# Forzar sync si es necesario
echo "🔄 Forzando sincronización de ArgoCD..."
kubectl patch application "proyecto-cloud-$ENVIRONMENT" -n argocd --type='merge' -p='{"operation":{"sync":{}}}' || {
  echo "⚠️ No se pudo forzar sync, pero continuamos..."
}

sleep 10

#########################################
# Verificar despliegue
#########################################
echo "📋 Verificando estado del despliegue..."

echo "🔍 Estado de ArgoCD Application:"
kubectl get applications -n argocd 2>/dev/null || echo "   - Error obteniendo applications"

echo ""
echo "🔍 Estado de los pods:"
kubectl get pods -n "$NAMESPACE" 2>/dev/null || echo "   - Esperando creación de pods..."

echo ""
echo "🔍 Estado de los services:"
kubectl get services -n "$NAMESPACE" 2>/dev/null || echo "   - Esperando creación de services..."

echo ""
echo "🔍 Estado de los secrets:"
kubectl get secrets -n "$NAMESPACE" 2>/dev/null || echo "   - Esperando creación de secrets..."

#########################################
# Información final
#########################################
echo ""
echo "🎉 ============================================"
echo "🎉 DESPLIEGUE GITOPS COMPLETADO"
echo "🎉 ============================================"
echo ""
echo "📊 Información del cluster:"
echo "   - Perfil: $PROFILE"
echo "   - Namespace: $NAMESPACE"
echo "   - Contexto: $CONTEXT"
echo "   - Método de despliegue: ArgoCD GitOps"
echo ""

# IP de Minikube
MINIKUBE_IP=$(minikube ip -p "$PROFILE")
echo "🌐 Accesos:"
echo "   - IP Minikube: $MINIKUBE_IP"

# Password de ArgoCD
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "No disponible")
echo "   - ArgoCD: http://$MINIKUBE_IP:30080"
echo "   - Usuario ArgoCD: admin"
echo "   - Password ArgoCD: $ARGOCD_PASSWORD"
echo ""

echo "🔧 Comandos útiles:"
echo "   kubectl get pods -n $NAMESPACE"
echo "   kubectl logs -f deployment/staging-backend-stg -n $NAMESPACE"
echo "   kubectl logs -f deployment/staging-frontend-stg -n $NAMESPACE"
echo "   kubectl get applications -n argocd"
echo "   minikube dashboard -p $PROFILE"
echo ""

echo "🔗 Para acceder a ArgoCD:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   Luego ir a: https://localhost:8080"
echo ""

echo "✅ ¡Despliegue GitOps completado exitosamente!"
echo "🎯 Tu aplicación está siendo gestionada por ArgoCD"
echo "🔐 Usando Sealed Secrets para credenciales seguras"
