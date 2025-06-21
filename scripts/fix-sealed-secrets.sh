#!/bin/bash
set -e

echo "🚀 SOLUCIÓN INMEDIATA - CREAR SECRETS DIRECTOS"
echo "=============================================="

NAMESPACE="proyecto-cloud-staging"

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

echo "🗑️ 1. Limpiar SealedSecrets problemáticos..."
kubectl delete sealedsecret staging-staging-app-secret-stg-stg -n $NAMESPACE --ignore-not-found=true
kubectl delete sealedsecret staging-staging-mysql-secret-stg-stg -n $NAMESPACE --ignore-not-found=true

echo "🔐 2. Crear secrets con nombres correctos..."

# Crear MySQL secret con el nombre exacto que espera Kustomize
kubectl create secret generic staging-mysql-secret-stg \
  --from-literal=username="$MYSQL_USER" \
  --from-literal=password="$MYSQL_PASSWORD" \
  --from-literal=root-password="$MYSQL_ROOT_PASSWORD" \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

# Crear App secret con el nombre exacto que espera Kustomize  
kubectl create secret generic staging-app-secret-stg \
  --from-literal=jwt-secret="$JWT_SECRET" \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ 3. Verificar secrets creados:"
kubectl get secrets -n $NAMESPACE

echo "🔄 4. Reiniciar pods para que tomen los nuevos secrets..."
kubectl delete pods -n $NAMESPACE -l app=backend --ignore-not-found=true
kubectl delete pods -n $NAMESPACE -l app=mysql --ignore-not-found=true

echo "⏳ 5. Esperando que los pods arranquen..."
sleep 15

echo "📋 6. Estado final de los pods:"
kubectl get pods -n $NAMESPACE

echo "🔍 7. Verificar si hay errores restantes:"
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -5

echo ""
echo "🎉 ==============================================="
echo "🎉 SOLUCIÓN APLICADA"
echo "🎉 ==============================================="
echo ""
echo "✅ Secrets creados con nombres correctos:"
echo "   - staging-mysql-secret-stg"
echo "   - staging-app-secret-stg"
echo ""
echo "⚠️ NOTA IMPORTANTE:"
echo "   - Los secrets están creados directamente (no via GitOps)"
echo "   - Esto es temporal hasta que arreglemos los Sealed Secrets"
echo "   - La aplicación debería funcionar ahora"
echo ""
echo "🔧 Comandos para verificar:"
echo "   kubectl get pods -n $NAMESPACE"
echo "   kubectl logs -f deployment/staging-backend-stg -n $NAMESPACE"
echo "   kubectl logs -f statefulset/staging-mysql-stg -n $NAMESPACE"
