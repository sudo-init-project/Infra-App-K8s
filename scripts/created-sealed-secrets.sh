#!/bin/bash
set -e

# Script para crear Sealed Secrets de forma segura
# Las credenciales se leen desde variables de entorno o .env

# Cargar variables desde .env si existe
if [ -f ".env" ]; then
  echo "🔐 Cargando variables desde .env"
  source .env
fi

# Valores por defecto si no están definidos
MYSQL_USER="${MYSQL_USER:-appuser}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-devpass123}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-rootpass123}"
JWT_SECRET="${JWT_SECRET:-GjPEfbM33noYJdEX4fymEken7svn6l81Xtnj9sX7Y7E=}"

echo "🔐 Creando Sealed Secrets..."

# Verificar que kubeseal esté instalado
if ! command -v kubeseal &> /dev/null; then
    echo "❌ kubeseal no está instalado. Ejecuta el script setup-sealed-secrets.sh primero"
    exit 1
fi

# Verificar que el controller esté corriendo
if ! kubectl get deployment sealed-secrets-controller -n kube-system >/dev/null 2>&1; then
    echo "❌ Sealed Secrets Controller no está instalado. Ejecuta el script setup-sealed-secrets.sh primero"
    exit 1
fi

# Crear directorio temporal
TEMP_DIR=$(mktemp -d)
echo "📁 Usando directorio temporal: $TEMP_DIR"

# 1. Crear Secret temporal para MySQL
cat << EOF > $TEMP_DIR/mysql-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret
  namespace: proyecto-cloud
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
  name: app-secret
  namespace: proyecto-cloud
type: Opaque
stringData:
  jwt-secret: $JWT_SECRET
EOF

# 3. Convertir a Sealed Secrets
echo "🔒 Convirtiendo MySQL secret a Sealed Secret..."
kubeseal -f $TEMP_DIR/mysql-secret.yaml -w base/mysql-sealed-secret.yaml

echo "🔒 Convirtiendo App secret a Sealed Secret..."
kubeseal -f $TEMP_DIR/app-secret.yaml -w base/app-sealed-secret.yaml

# 4. Limpiar archivos temporales
rm -rf $TEMP_DIR

echo "✅ Sealed Secrets creados en:"
echo "   - base/mysql-sealed-secret.yaml"
echo "   - base/app-sealed-secret.yaml"
echo ""
echo "🎯 Estos archivos SÍ se pueden commitear a Git de forma segura"
echo "🔐 Solo se pueden descifrar en el cluster donde se crearon"
echo ""
echo "📝 Próximos pasos:"
echo "   1. git add base/*-sealed-secret.yaml"
echo "   2. git commit -m 'Add sealed secrets'"
echo "   3. git push"
