#!/bin/bash
set -e

#########################################
# Script para desplegar ambiente completo
#########################################

ENVIRONMENT=${1:-staging}
CPUS=${2:-4}
MEMORY=${3:-8192}

# Variables de entorno por defecto (pueden ser sobrescritas)
export MYSQL_USER="${MYSQL_USER:-appuser}"
export MYSQL_PASSWORD="${MYSQL_PASSWORD:-devpass123}"
export MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-rootpass123}"
export JWT_SECRET="${JWT_SECRET:-GjPEfbM33noYJdEX4fymEken7svn6l81Xtnj9sX7Y7E=}"

clear
echo "🚀 ============================================"
echo "🚀 DESPLEGANDO AMBIENTE: $ENVIRONMENT"
echo "🚀 ============================================"
date
echo ""

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
for cmd in minikube kubectl envsubst; do
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
    --addons=metrics-server,dashboard,ingress
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
# Aplicar secrets con variables de entorno
#########################################
echo "🔐 Aplicando secrets para ambiente $ENVIRONMENT..."
# Crear el namespace primero si no existe
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Aplicar secrets usando envsubst
envsubst < base/secrets.yaml | kubectl apply -f -
echo "✅ Secrets aplicados"
echo ""

#########################################
# Desplegar aplicación usando Kustomize
#########################################
echo "🚀 Desplegando aplicación en ambiente $ENVIRONMENT usando Kustomize..."

# Aplicar la configuración base + overlay del ambiente
kubectl apply -k overlays/$ENVIRONMENT

echo "⏳ Esperando a que la aplicación esté lista..."
kubectl wait --for=condition=available deployment --all -n "$NAMESPACE" --timeout=300s

#########################################
# Obtener información de acceso
#########################################
echo ""
echo "🎉 ============================================"
echo "🎉 DESPLIEGUE COMPLETADO"
echo "🎉 ============================================"
echo ""
echo "📊 Información del cluster:"
echo "   - Perfil: $PROFILE"
echo "   - Namespace: $NAMESPACE"
echo "   - Contexto: $CONTEXT"
echo ""

# IP de Minikube
MINIKUBE_IP=$(minikube ip -p "$PROFILE")
echo "🌐 Accesos:"
echo "   - IP Minikube: $MINIKUBE_IP"

# Password de ArgoCD
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "   - ArgoCD: http://$MINIKUBE_IP:30080"
echo "   - Usuario ArgoCD: admin"
echo "   - Password ArgoCD: $ARGOCD_PASSWORD"
echo ""

# Servicios de la aplicación
echo "📱 Servicios desplegados:"
kubectl get services -n "$NAMESPACE" 2>/dev/null || echo "   - Esperando despliegue..."
echo ""

echo "🔧 Comandos útiles:"
echo "   kubectl get pods -n $NAMESPACE"
echo "   kubectl logs -f deployment/frontend -n $NAMESPACE"
echo "   minikube dashboard -p $PROFILE"
echo ""

# Port-forward para ArgoCD si no hay ingress
echo "🔗 Para acceder a ArgoCD:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   Luego ir a: http://localhost:8080"
echo ""

echo "✅ ¡Despliegue completado exitosamente!"
