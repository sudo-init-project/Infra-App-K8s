#!/bin/bash
set -e

#########################################
# Script para generar Sealed Secrets 
# compatibles con el cluster actual
#########################################

ENVIRONMENT=${1:-staging}
NAMESPACE="proyecto-cloud-$ENVIRONMENT"

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

echo "🔐 ============================================"
echo "🔐 GENERANDO SEALED SECRETS PARA: $ENVIRONMENT"
echo "🔐 ============================================"

#########################################
# Verificar dependencias
#########################################
echo "🔍 Verificando dependencias..."

# Verificar kubectl
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl no está instalado"
    exit 1
fi

# Verificar que el cluster esté accesible
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ No se puede conectar al cluster de Kubernetes"
    echo "💡 Asegúrate de que minikube esté corriendo y el contexto esté configurado"
    exit 1
fi

echo "✅ Cluster accesible"

#########################################
# Instalar Sealed Secrets Controller si no existe
#########################################
echo "🔧 Verificando Sealed Secrets Controller..."

if ! kubectl get deployment sealed-secrets-controller -n kube-system >/dev/null 2>&1; then
    echo "🚀 Instalando Sealed Secrets Controller..."
    kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml
    
    echo "⏳ Esperando a que el controller esté listo..."
    kubectl wait --for=condition=available deployment/sealed-secrets-controller -n kube-system --timeout=120s
else
    echo "✅ Sealed Secrets Controller ya está instalado"
fi

#########################################
# Instalar kubeseal CLI si no existe
#########################################
echo "🔧 Verificando kubeseal CLI..."

if ! command -v kubeseal &> /dev/null; then
    echo "📥 Instalando kubeseal CLI..."
    KUBESEAL_VERSION='0.24.0'
    
    # Detectar OS
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        arm64|aarch64) ARCH="arm64" ;;
    esac
    
    # Descargar kubeseal
    KUBESEAL_URL="https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-${OS}-${ARCH}.tar.gz"
    
    echo "📡 Descargando desde: $KUBESEAL_URL"
    wget -q "$KUBESEAL_URL" -O kubeseal.tar.gz
    tar -xzf kubeseal.tar.gz kubeseal
    sudo mv kubeseal /usr/local/bin/kubeseal
    rm kubeseal.tar.gz
    
    echo "✅ kubeseal instalado correctamente"
else
    echo "✅ kubeseal ya está instalado"
fi

#########################################
# Crear namespace si no existe
#########################################
echo "🎯 Verificando namespace $NAMESPACE..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

#########################################
# Generar Sealed Secrets
#########################################
echo "🔒 Generando Sealed Secrets para el cluster actual..."

# Crear directorio temporal
TEMP_DIR=$(mktemp -d)
echo "📁 Usando directorio temporal: $TEMP_DIR"

# Prefijos para el ambiente
case "$ENVIRONMENT" in
  staging)
    PREFIX="staging-"
    SUFFIX="-stg"
    ;;
  production)
    PREFIX="prod-"
    SUFFIX="-prod"
    ;;
  dev)
    PREFIX="dev-"
    SUFFIX="-dev"
    ;;
  *)
    PREFIX=""
    SUFFIX=""
    ;;
esac

MYSQL_SECRET_NAME="${PREFIX}mysql-secret${SUFFIX}"
APP_SECRET_NAME="${PREFIX}app-secret${SUFFIX}"

echo "🏷️ Nombres de secrets:"
echo "   - MySQL: $MYSQL_SECRET_NAME"
echo "   - App: $APP_SECRET_NAME"

# 1. Crear Secret temporal para MySQL
cat << EOF > $TEMP_DIR/mysql-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: $MYSQL_SECRET_NAME
  namespace: $NAMESPACE
type: Opaque
stringData:
  username: $MYSQL_USER
  password: $MYSQL_PASSWORD
  root-password: $MYSQL_ROOT_PASSWORD
EOF

# 2. Crear Secret temporal para App
cat << EOF > $TEMP_DIR/app-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: $APP_SECRET_NAME
  namespace: $NAMESPACE
type: Opaque
stringData:
  jwt-secret: $JWT_SECRET
EOF

# 3. Convertir a Sealed Secrets
echo "🔒 Convirtiendo MySQL secret a Sealed Secret..."
kubeseal -f $TEMP_DIR/mysql-secret.yaml -w overlays/$ENVIRONMENT/mysql-sealed-secret.yaml

echo "🔒 Convirtiendo App secret a Sealed Secret..."
kubeseal -f $TEMP_DIR/app-secret.yaml -w overlays/$ENVIRONMENT/app-sealed-secret.yaml

# 4. Limpiar archivos temporales
rm -rf $TEMP_DIR

echo "✅ Sealed Secrets generados en:"
echo "   - overlays/$ENVIRONMENT/mysql-sealed-secret.yaml"
echo "   - overlays/$ENVIRONMENT/app-sealed-secret.yaml"
echo ""

#########################################
# Actualizar kustomization.yaml
#########################################
echo "📝 Actualizando kustomization.yaml..."

KUSTOMIZATION_FILE="overlays/$ENVIRONMENT/kustomization.yaml"

# Crear backup
cp "$KUSTOMIZATION_FILE" "$KUSTOMIZATION_FILE.backup"

# Agregar sealed secrets al kustomization si no están
if ! grep -q "mysql-sealed-secret.yaml" "$KUSTOMIZATION_FILE"; then
    echo "➕ Agregando mysql-sealed-secret.yaml a resources"
    sed -i '/resources:/a\  - mysql-sealed-secret.yaml' "$KUSTOMIZATION_FILE"
fi

if ! grep -q "app-sealed-secret.yaml" "$KUSTOMIZATION_FILE"; then
    echo "➕ Agregando app-sealed-secret.yaml a resources"
    sed -i '/resources:/a\  - app-sealed-secret.yaml' "$KUSTOMIZATION_FILE"
fi

echo "✅ Kustomization actualizado"

#########################################
# Información final
#########################################
echo ""
echo "🎉 ============================================"
echo "🎉 SEALED SECRETS GENERADOS EXITOSAMENTE"
echo "🎉 ============================================"
echo ""
echo "📋 Archivos generados:"
echo "   - overlays/$ENVIRONMENT/mysql-sealed-secret.yaml"
echo "   - overlays/$ENVIRONMENT/app-sealed-secret.yaml"
echo "   - overlays/$ENVIRONMENT/kustomization.yaml (actualizado)"
echo ""
echo "🔐 Estos archivos SÍ se pueden commitear a Git de forma segura"
echo "🎯 Solo se pueden descifrar en ESTE cluster específico"
echo ""
echo "📝 Próximos pasos:"
echo "   1. git add overlays/$ENVIRONMENT/"
echo "   2. git commit -m 'Add sealed secrets for $ENVIRONMENT'"
echo "   3. git push"
echo "   4. ArgoCD detectará los cambios y desplegará automáticamente"
echo ""
echo "🔄 Para forzar sync en ArgoCD:"
echo "   kubectl patch application proyecto-cloud-$ENVIRONMENT -n argocd --type='merge' -p='{\"operation\":{\"sync\":{}}}'"
