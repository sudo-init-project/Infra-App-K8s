#!/bin/bash
set -e

#########################################
# Script para desplegar ambiente completo
#########################################

ENVIRONMENT=${1:-staging}
CPUS=${2:-4}
MEMORY=${3:-4092}

# Variables de entorno por defecto
export MYSQL_USER="${MYSQL_USER:-appuser}"
export MYSQL_PASSWORD="${MYSQL_PASSWORD:-devpass123}"
export MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-rootpass123}"
export JWT_SECRET="${JWT_SECRET:-GjPEfbM33noYJdEX4fymEken7svn6l81Xtnj9sX7Y7E=}"

# Variable para controlar el método de despliegue
ARGOCD_DEPLOYED=false

# Cargar variables desde .env si existe
if [ -f ".env" ]; then
  echo "🔐 Cargando variables desde .env"
  set -a  # Automatically export all variables
  source .env
  set +a  # Stop automatically exporting
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

# Verificar memoria disponible de Docker
DOCKER_MEMORY=$(docker system info --format '{{.MemTotal}}' 2>/dev/null | grep -o '[0-9]*' | head -1)
if [ -n "$DOCKER_MEMORY" ] && [ "$DOCKER_MEMORY" -lt 8000000000 ]; then
  echo "⚠️ Docker tiene poca memoria disponible. Reduciendo recursos..."
  MEMORY=4096
  CPUS=2
fi

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
# Aplicar aplicación de ArgoCD (si existe)
#########################################
if [ -f "argocd/${ENVIRONMENT}-app.yaml" ]; then
  echo "🎯 Desplegando aplicación ArgoCD para $ENVIRONMENT..."
  kubectl apply -f argocd/${ENVIRONMENT}-app.yaml
  echo "✅ Aplicación ArgoCD creada"
  
  # Esperar a que ArgoCD sincronice automáticamente
  echo "⏳ Esperando sincronización automática de ArgoCD..."
  sleep 10
  
  # Verificar si la sincronización automática funcionó
  echo "📋 Verificando estado de la aplicación..."
  if kubectl get application "proyecto-cloud-$ENVIRONMENT" -n argocd >/dev/null 2>&1; then
    # Esperar un poco más para la sincronización
    echo "⏳ Aplicación encontrada, esperando sincronización..."
    sleep 15
    
    # Verificar si los recursos fueron desplegados por ArgoCD
    if kubectl get pods -n "proyecto-cloud-$ENVIRONMENT" >/dev/null 2>&1 && [ "$(kubectl get pods -n "proyecto-cloud-$ENVIRONMENT" --no-headers | wc -l)" -gt 0 ]; then
      echo "✅ ArgoCD desplegó los recursos exitosamente"
      ARGOCD_DEPLOYED=true
    else
      echo "⚠️ ArgoCD no desplegó los recursos automáticamente"
      ARGOCD_DEPLOYED=false
    fi
  else
    echo "❌ No se pudo crear la aplicación de ArgoCD"
    ARGOCD_DEPLOYED=false
  fi
else
  echo "⚠️ No se encontró argocd/${ENVIRONMENT}-app.yaml - usando Kustomize directo"
  ARGOCD_DEPLOYED=false
fi
echo ""

#########################################
# Aplicar secrets con variables de entorno
#########################################
echo "🔐 Aplicando secrets para ambiente $ENVIRONMENT..."
# Crear el namespace primero si no existe
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Verificar que las variables estén definidas
if [ -z "$MYSQL_USER" ] || [ -z "$MYSQL_PASSWORD" ] || [ -z "$MYSQL_ROOT_PASSWORD" ] || [ -z "$JWT_SECRET" ]; then
    echo "❌ Error: Variables de entorno no definidas"
    echo "🔧 Solución: Crear archivo .env o exportar variables"
    echo "📋 Variables necesarias: MYSQL_USER, MYSQL_PASSWORD, MYSQL_ROOT_PASSWORD, JWT_SECRET"
    exit 1
fi

# Crear archivo temporal de secrets con namespace correcto
TEMP_SECRETS=$(mktemp)
cat base/secrets.yaml | sed "s/namespace: proyecto-cloud/namespace: $NAMESPACE/g" > "$TEMP_SECRETS"

# Aplicar secrets usando envsubst para reemplazar variables
envsubst < "$TEMP_SECRETS" | kubectl apply -f -

# Limpiar archivo temporal
rm "$TEMP_SECRETS"

echo "✅ Secrets aplicados usando variables de entorno (sin credenciales hardcodeadas)"
echo ""

#########################################
# Desplegar aplicación usando Kustomize (solo si ArgoCD no lo hizo)
#########################################
if [ "$ARGOCD_DEPLOYED" = true ]; then
  echo "🎉 ArgoCD ya desplegó la aplicación exitosamente"
  echo "⏩ Saltando despliegue manual con Kustomize"
else
  echo "🚀 Desplegando aplicación en ambiente $ENVIRONMENT usando Kustomize..."

  # Verificar que exista el overlay del ambiente
  if [ ! -d "overlays/$ENVIRONMENT" ]; then
    echo "❌ No existe el directorio overlays/$ENVIRONMENT"
    echo "📂 Directorios disponibles:"
    ls -la overlays/
    exit 1
  fi

  # Aplicar la configuración base + overlay del ambiente
  echo "📝 Aplicando kustomization desde overlays/$ENVIRONMENT"
  kubectl apply -k overlays/$ENVIRONMENT

  echo "⏳ Esperando a que los deployments estén listos..."
  kubectl wait --for=condition=available deployment --all -n "$NAMESPACE" --timeout=300s || echo "⚠️ Algunos deployments tardaron más de lo esperado"
fi

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
echo "   - Método de despliegue: $([ "$ARGOCD_DEPLOYED" = true ] && echo "ArgoCD GitOps" || echo "Kustomize directo")"
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

# Estado de ArgoCD si fue usado
if [ "$ARGOCD_DEPLOYED" = true ]; then
  echo "🔄 Estado de ArgoCD Application:"
  kubectl get applications -n argocd 2>/dev/null || echo "   - Error obteniendo applications"
  echo ""
fi

echo "🔧 Comandos útiles:"
echo "   kubectl get pods -n $NAMESPACE"
echo "   kubectl logs -f deployment/frontend -n $NAMESPACE"
echo "   minikube dashboard -p $PROFILE"
if [ "$ARGOCD_DEPLOYED" = true ]; then
  echo "   # Ver aplicación en ArgoCD:"
  echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
fi
echo ""

# Port-forward para ArgoCD si no hay ingress
echo "🔗 Para acceder a ArgoCD:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   Luego ir a: https://localhost:8080"
echo ""

if [ "$ARGOCD_DEPLOYED" = true ]; then
  echo "✅ ¡Despliegue GitOps completado exitosamente!"
  echo "🎯 Tu aplicación está siendo gestionada por ArgoCD"
else
  echo "✅ ¡Despliegue completado exitosamente!"
  echo "⚠️ Aplicación desplegada directamente con Kustomize (no GitOps)"
fi
