#!/bin/bash
set -e

#########################################
# Script para desplegar ambiente completo
# VERSIÓN CORREGIDA - SIN ARGOCD
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
# Crear namespace
#########################################
echo "🎯 Creando namespace $NAMESPACE..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
echo ""

#########################################
# ELIMINAR ArgoCD Application si existe
#########################################
echo "🗑️ Eliminando aplicación ArgoCD existente (para evitar conflictos)..."
kubectl delete application "proyecto-cloud-$ENVIRONMENT" -n argocd --ignore-not-found=true
echo ""

#########################################
# Crear secrets directamente (sin ArgoCD)
#########################################
echo "🔐 Creando secrets para ambiente $ENVIRONMENT..."

# Verificar que las variables estén definidas
if [ -z "$MYSQL_USER" ] || [ -z "$MYSQL_PASSWORD" ] || [ -z "$MYSQL_ROOT_PASSWORD" ] || [ -z "$JWT_SECRET" ]; then
    echo "❌ Error: Variables de entorno no definidas"
    echo "🔧 Solución: Crear archivo .env o exportar variables"
    echo "📋 Variables necesarias: MYSQL_USER, MYSQL_PASSWORD, MYSQL_ROOT_PASSWORD, JWT_SECRET"
    exit 1
fi

# Mostrar variables (sin mostrar passwords completos)
echo "🔍 Variables definidas:"
echo "   MYSQL_USER: $MYSQL_USER"
echo "   MYSQL_PASSWORD: ${MYSQL_PASSWORD:0:3}***"
echo "   MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD:0:3}***"
echo "   JWT_SECRET: ${JWT_SECRET:0:20}..."

# Crear MySQL secret
kubectl create secret generic mysql-secret \
  --from-literal=username="$MYSQL_USER" \
  --from-literal=password="$MYSQL_PASSWORD" \
  --from-literal=root-password="$MYSQL_ROOT_PASSWORD" \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

# Crear App secret
kubectl create secret generic app-secret \
  --from-literal=jwt-secret="$JWT_SECRET" \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Secrets creados directamente en el cluster"
echo ""

#########################################
# Desplegar aplicación usando Kustomize
#########################################
echo "🚀 Desplegando aplicación en ambiente $ENVIRONMENT usando Kustomize..."

# Verificar que exista el overlay del ambiente
if [ ! -d "overlays/$ENVIRONMENT" ]; then
  echo "❌ No existe el directorio overlays/$ENVIRONMENT"
  echo "📂 Directorios disponibles:"
  ls -la overlays/ 2>/dev/null || echo "   - No hay overlays configurados"
  
  # Usar base si no hay overlay específico
  echo "⚠️ Usando configuración base..."
  KUSTOMIZE_PATH="base"
else
  KUSTOMIZE_PATH="overlays/$ENVIRONMENT"
fi

# Aplicar la configuración
echo "📝 Aplicando kustomization desde $KUSTOMIZE_PATH"
kubectl apply -k "$KUSTOMIZE_PATH"

echo "⏳ Esperando a que los deployments estén listos..."
kubectl wait --for=condition=available deployment --all -n "$NAMESPACE" --timeout=300s || {
  echo "⚠️ Algunos deployments tardaron más de lo esperado"
  echo "📋 Estado actual de los pods:"
  kubectl get pods -n "$NAMESPACE"
}

#########################################
# Verificar estado de la aplicación
#########################################
echo ""
echo "📋 Verificando estado de la aplicación..."
kubectl get pods -n "$NAMESPACE"
echo ""
kubectl get services -n "$NAMESPACE"
echo ""

# Verificar secrets
echo "🔐 Verificando secrets:"
kubectl get secrets -n "$NAMESPACE"
echo ""

#########################################
# Información final
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
echo "   - Método de despliegue: Kustomize directo (sin GitOps)"
echo ""

# IP de Minikube
MINIKUBE_IP=$(minikube ip -p "$PROFILE")
echo "🌐 Accesos:"
echo "   - IP Minikube: $MINIKUBE_IP"
echo ""

echo "🔧 Comandos útiles:"
echo "   kubectl get pods -n $NAMESPACE"
echo "   kubectl logs -f deployment/backend -n $NAMESPACE"
echo "   kubectl logs -f deployment/frontend -n $NAMESPACE"
echo "   kubectl logs -f statefulset/mysql -n $NAMESPACE"
echo "   minikube dashboard -p $PROFILE"
echo ""

echo "🐛 Para debugging:"
echo "   kubectl describe pods -n $NAMESPACE"
echo "   kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
echo ""

echo "✅ ¡Despliegue completado!"
echo "🎯 Aplicación desplegada directamente con Kustomize"
echo "⚠️ Los secrets se crean localmente (no están en GitOps)"
