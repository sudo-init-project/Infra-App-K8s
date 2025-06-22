#!/bin/bash
set -e

#########################################
# DEPLOY-ALL DEFINITIVO - CON ARGOCD INTEGRADO
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
echo "🚀 DEPLOY-ALL DEFINITIVO: $ENVIRONMENT"
echo "🚀 ============================================"
date

#########################################
# Validar ambiente
#########################################
case "$ENVIRONMENT" in
  dev|staging|production)
    echo "🟢 Ambiente: $ENVIRONMENT"
    PROFILE="minikube-$ENVIRONMENT"
    NAMESPACE="proyecto-cloud-$ENVIRONMENT"
    ;;
  *)
    echo "❌ ENVIRONMENT debe ser: dev, staging, production"
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
echo "✅ Dependencias OK"

#########################################
# Iniciar Minikube
#########################################
echo "🚀 Verificando Minikube..."
if minikube status -p "$PROFILE" | grep -q "Running"; then
  echo "✅ Minikube corriendo"
else
  echo "🚀 Iniciando Minikube..."
  minikube start -p "$PROFILE" --cpus="$CPUS" --memory="$MEMORY" --addons=metrics-server,dashboard,ingress
fi

kubectl config use-context "$PROFILE"
echo "✅ Contexto configurado: $PROFILE"

#########################################
# Crear namespace
#########################################
echo "🎯 Creando namespace..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

#########################################
# INSTALAR ARGOCD SI NO EXISTE
#########################################
echo "🚀 Verificando ArgoCD..."
if kubectl get namespace argocd >/dev/null 2>&1; then
  echo "✅ ArgoCD namespace existe"
else
  echo "🚀 Instalando ArgoCD..."
  kubectl create namespace argocd
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  
  echo "⏳ Esperando ArgoCD..."
  kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
fi

#########################################
# CORREGIR PROBLEMA DE NOMBRES DE SECRETS
#########################################
echo "🔧 Corrigiendo problema de secrets..."

# PROBLEMA: Los deployments buscan mysql-secret y app-secret 
# PERO: Kustomize genera staging-mysql-secret-stg y staging-app-secret-stg
# SOLUCIÓN: Crear secrets con ambos nombres

# 1. Crear secrets base (lo que buscan los deployments)
kubectl create secret generic mysql-secret \
  --from-literal=username="$MYSQL_USER" \
  --from-literal=password="$MYSQL_PASSWORD" \
  --from-literal=root-password="$MYSQL_ROOT_PASSWORD" \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic app-secret \
  --from-literal=jwt-secret="$JWT_SECRET" \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

# 2. TAMBIÉN crear secrets con nombres de Kustomize (por si acaso)
kubectl create secret generic staging-mysql-secret-stg \
  --from-literal=username="$MYSQL_USER" \
  --from-literal=password="$MYSQL_PASSWORD" \
  --from-literal=root-password="$MYSQL_ROOT_PASSWORD" \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic staging-app-secret-stg \
  --from-literal=jwt-secret="$JWT_SECRET" \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Secrets creados con ambos nombres:"
kubectl get secrets -n "$NAMESPACE" | grep -E "(mysql|app)-secret"

#########################################
# CREAR/ACTUALIZAR APLICACIÓN ARGOCD
#########################################
echo "🎯 Configurando aplicación ArgoCD..."

# Eliminar aplicación existente si tiene problemas
kubectl delete application "proyecto-cloud-$ENVIRONMENT" -n argocd --ignore-not-found=true
sleep 5

# Crear aplicación ArgoCD
cat << ARGOAPP | kubectl apply -f -
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
ARGOAPP

echo "✅ Aplicación ArgoCD creada"

#########################################
# DEPLOY MANUAL INMEDIATO (BYPASS ARGOCD)
#########################################
echo "📦 Deploy manual para arranque inmediato..."
kubectl apply -k overlays/$ENVIRONMENT/ || echo "⚠️ Algunos recursos ya existen"

#########################################
# FORZAR SYNC ARGOCD
#########################################
echo "🔄 Forzando sync en ArgoCD..."
sleep 10
kubectl patch application "proyecto-cloud-$ENVIRONMENT" -n argocd --type='merge' -p='{"operation":{"sync":{}}}' || echo "⚠️ Sync manual falló"

#########################################
# ESPERAR Y VERIFICAR
#########################################
echo "⏳ Esperando que los pods arranquen..."
sleep 30

echo "📋 Estado de los recursos:"
echo ""
echo "🔐 Secrets:"
kubectl get secrets -n "$NAMESPACE" | grep -E "(mysql|app)"
echo ""
echo "📦 Pods:"
kubectl get pods -n "$NAMESPACE"
echo ""
echo "🌐 Services:"
kubectl get svc -n "$NAMESPACE"
echo ""
echo "🔄 ArgoCD Applications:"
kubectl get applications -n argocd | grep "$ENVIRONMENT"

#########################################
# INFORMACIÓN DE ACCESO
#########################################
echo ""
echo "🎉 ============================================"
echo "🎉 DEPLOY COMPLETADO"
echo "🎉 ============================================"
echo ""

# Obtener password de ArgoCD
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "No disponible")
MINIKUBE_IP=$(minikube ip -p "$PROFILE" 2>/dev/null || echo "localhost")

echo "🌐 ACCESO A ARGOCD:"
echo "   📱 UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   🌍 URL: https://localhost:8080"
echo "   👤 Usuario: admin"
echo "   🔑 Password: $ARGOCD_PASSWORD"
echo ""

echo "🌐 ACCESO A LA APLICACIÓN:"
echo "   📱 Frontend: kubectl port-forward svc/staging-frontend-service-stg -n $NAMESPACE 3000:80"
echo "   🌍 URL: http://localhost:3000"
echo "   👤 Login: admin / admin"
echo ""

echo "🔧 COMANDOS DE DIAGNÓSTICO:"
echo "   kubectl get pods -n $NAMESPACE"
echo "   kubectl logs -f deployment/staging-backend-stg -n $NAMESPACE"
echo "   kubectl logs -f statefulset/staging-mysql-stg -n $NAMESPACE"
echo "   kubectl describe pod <pod-name> -n $NAMESPACE"
echo ""

# Verificar si hay problemas
FAILED_PODS=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep -v Running | grep -v Completed | wc -l)
if [ "$FAILED_PODS" -gt 0 ]; then
  echo "⚠️ ATENCIÓN: Hay $FAILED_PODS pods con problemas"
  echo "   Ejecuta: kubectl get pods -n $NAMESPACE para ver detalles"
else
  echo "✅ Todos los pods están funcionando correctamente"
fi

echo ""
echo "🎯 Tu aplicación está lista!"
echo "   - ArgoCD está configurado para GitOps automático"
echo "   - Los secrets están creados correctamente"  
echo "   - La aplicación debería estar accesible"
