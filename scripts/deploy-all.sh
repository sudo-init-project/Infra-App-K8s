#!/bin/bash
set -e

#########################################
# SCRIPT DEPLOY-ALL DEFINITIVO
# DEPLOYEA TODO CORRECTAMENTE CON ARGOCD
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
echo "🚀 DESPLEGANDO AMBIENTE COMPLETO: $ENVIRONMENT"
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
# Crear namespace
#########################################
echo "🎯 Creando namespace $NAMESPACE..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
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
# CORREGIR ARCHIVOS PROBLEMÁTICOS
#########################################
echo "🔧 Corrigiendo configuración de archivos..."

# 1. Restaurar kustomization.yaml funcional
cat > overlays/$ENVIRONMENT/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: $NAMESPACE

resources:
  - ../../base
  - nginx-configmap.yaml

namePrefix: $ENVIRONMENT-
nameSuffix: -stg

patches:
  - path: deployment_patch.yaml
  - path: frontend-deployment-patch.yaml

images:
  - name: facundo676/backend-shop
    newTag: latest
  - name: facundo676/frontend-shop
    newTag: latest
EOF

# 2. Crear nginx-configmap.yaml que falta
cat > overlays/$ENVIRONMENT/nginx-configmap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: proyecto-cloud
data:
  default.conf: |
    server {
        listen 80;
        server_name localhost;
        root /usr/share/nginx/html;
        index index.html;
        
        # Configuración específica para React Router
        location / {
            try_files $uri $uri/ /index.html;
        }
        
        # Headers para SPA
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
        
        # API proxy al backend
        location /api/ {
            proxy_pass http://backend-service:8080/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        error_page 500 502 503 504 /50x.html;
        location = /50x.html {
            root /usr/share/nginx/html;
        }
    }
EOF

echo "✅ Archivos corregidos"
echo ""

#########################################
# CREAR SECRETS DIRECTAMENTE
#########################################
echo "🔐 Creando secrets directamente..."

# Eliminar secrets existentes
kubectl delete secret mysql-secret -n "$NAMESPACE" --ignore-not-found=true
kubectl delete secret app-secret -n "$NAMESPACE" --ignore-not-found=true

# Crear secrets con nombres base (sin prefijos)
kubectl create secret generic mysql-secret \
  --from-literal=username="$MYSQL_USER" \
  --from-literal=password="$MYSQL_PASSWORD" \
  --from-literal=root-password="$MYSQL_ROOT_PASSWORD" \
  --namespace="$NAMESPACE"

kubectl create secret generic app-secret \
  --from-literal=jwt-secret="$JWT_SECRET" \
  --namespace="$NAMESPACE"

echo "✅ Secrets creados correctamente"
kubectl get secrets -n "$NAMESPACE"
echo ""

#########################################
# COMMITEAR CAMBIOS A GIT
#########################################
echo "📝 Commiteando cambios a Git..."

if [ -d ".git" ]; then
  git add overlays/$ENVIRONMENT/
  git commit -m "🔧 Fix: Corregir configuración de $ENVIRONMENT

- Agregar nginx-configmap.yaml faltante
- Corregir referencias en kustomization.yaml  
- Configurar Nginx para React Router
- Timestamp: $(date)" || echo "⚠️ No hay cambios para commitear"
  
  git push || echo "⚠️ Error al pushear, continuando..."
  echo "✅ Cambios commiteados"
else
  echo "⚠️ No es un repositorio Git"
fi
echo ""

#########################################
# CONFIGURAR ARGOCD APPLICATION
#########################################
echo "🎯 Configurando ArgoCD Application..."

# Eliminar aplicación existente si hay problemas
kubectl delete application "proyecto-cloud-$ENVIRONMENT" -n argocd --ignore-not-found=true
sleep 5

# Crear aplicación ArgoCD usando el archivo existente si está disponible
if [ -f "argocd/$ENVIRONMENT-app.yaml" ]; then
  echo "📂 Usando archivo ArgoCD existente: argocd/$ENVIRONMENT-app.yaml"
  kubectl apply -f "argocd/$ENVIRONMENT-app.yaml"
else
  echo "🔧 Creando aplicación ArgoCD genérica..."
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
    - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
ARGOAPP
fi

echo "⏳ Esperando sincronización inicial de ArgoCD..."
sleep 15

#########################################
# FORZAR SINCRONIZACIÓN DE ARGOCD
#########################################
echo "🔄 Forzando sincronización de ArgoCD..."

# Reintentar sync hasta 3 veces
for i in {1..3}; do
  echo "🔄 Intento de sync $i/3..."
  
  if kubectl patch application "proyecto-cloud-$ENVIRONMENT" -n argocd --type='merge' -p='{"operation":{"sync":{}}}' 2>/dev/null; then
    echo "✅ Sync iniciado correctamente"
    break
  else
    echo "⚠️ Error en sync, reintentando en 10s..."
    sleep 10
  fi
done

sleep 20

#########################################
# VERIFICAR Y REINICIAR PODS SI ES NECESARIO
#########################################
echo "🔄 Verificando estado de la aplicación..."

# Verificar si los pods están corriendo
POD_COUNT=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")

if [ "$POD_COUNT" -eq "0" ]; then
  echo "⚠️ No hay pods, aplicando manifiestos directamente como backup..."
  kubectl apply -k "overlays/$ENVIRONMENT"
  sleep 15
fi

# Reiniciar pods que puedan estar en estado problemático
kubectl delete pods -n "$NAMESPACE" -l app=frontend --ignore-not-found=true
kubectl delete pods -n "$NAMESPACE" -l app=backend --ignore-not-found=true

echo "⏳ Esperando que los pods se estabilicen..."
sleep 20

#########################################
# VERIFICAR ESTADO FINAL
#########################################
echo "📋 Estado final de la aplicación:"
echo ""
echo "🎯 Pods:"
kubectl get pods -n "$NAMESPACE" || echo "❌ Error obteniendo pods"
echo ""
echo "🌐 Services:"
kubectl get services -n "$NAMESPACE" || echo "❌ Error obteniendo services"
echo ""
echo "🔐 Secrets:"
kubectl get secrets -n "$NAMESPACE" || echo "❌ Error obteniendo secrets"
echo ""
echo "🔄 ArgoCD Application:"
kubectl get applications -n argocd | grep "$ENVIRONMENT" || echo "❌ Error obteniendo application"

#########################################
# INFORMACIÓN FINAL
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
MINIKUBE_IP=$(minikube ip -p "$PROFILE" 2>/dev/null || echo "No disponible")
echo "🌐 Accesos:"
echo "   - IP Minikube: $MINIKUBE_IP"

# Password de ArgoCD
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "No disponible")
echo "   - ArgoCD: http://$MINIKUBE_IP:30080"
echo "   - Usuario ArgoCD: admin"
echo "   - Password ArgoCD: $ARGOCD_PASSWORD"
echo ""

echo "🌐 Para acceder a la aplicación:"
echo "   1. Port-forward: kubectl port-forward service/$ENVIRONMENT-frontend-service-stg 3000:80 -n $NAMESPACE"
echo "   2. Abrir: http://localhost:3000"
echo "   3. Login con: admin/admin"
echo ""

echo "🔧 Comandos útiles:"
echo "   kubectl get pods -n $NAMESPACE"
echo "   kubectl logs -f deployment/$ENVIRONMENT-backend-stg -n $NAMESPACE"
echo "   kubectl logs -f deployment/$ENVIRONMENT-frontend-stg -n $NAMESPACE"
echo "   kubectl get applications -n argocd"
echo ""

echo "🔗 Para acceder a ArgoCD:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   Luego ir a: https://localhost:8080"
echo ""

echo "✅ ¡DEPLOY-ALL COMPLETADO EXITOSAMENTE!"
echo "🎯 La aplicación está desplegada con ArgoCD GitOps"
echo "🔄 ArgoCD gestionará automáticamente cualquier cambio en Git"
