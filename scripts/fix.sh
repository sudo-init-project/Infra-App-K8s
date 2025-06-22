#!/bin/bash
set -e

echo "🚀 SOLUCIÓN COMPLETA - ARREGLAR TODO"
echo "==================================="

NAMESPACE="proyecto-cloud-staging"

# Variables
export MYSQL_USER="${MYSQL_USER:-appuser}"
export MYSQL_PASSWORD="${MYSQL_PASSWORD:-devpass123}"
export MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-rootpass123}"
export JWT_SECRET="${JWT_SECRET:-GjPEfbM33noYJdEX4fymEken7svn6l81Xtnj9sX7Y7E=}"

if [ -f ".env" ]; then
  source .env
fi

echo "🔐 1. Crear secrets directos (bypass sealed secrets)..."
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

echo "✅ Secrets creados"

echo "📦 2. Deploy manual directo (bypass ArgoCD temporalmente)..."
kubectl apply -k overlays/staging/

echo "✅ Manifiestos aplicados"

echo "🎯 3. Crear aplicación ArgoCD..."
cat << 'ARGOAPP' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: proyecto-cloud-staging
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/sudo-init-project/Infra-App-K8s
    targetRevision: HEAD
    path: overlays/staging
  destination:
    server: https://kubernetes.default.svc
    namespace: proyecto-cloud-staging
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
ARGOAPP

echo "✅ Aplicación ArgoCD creada"

echo "⏳ 4. Esperando pods..."
sleep 30

echo "📋 5. Estado actual:"
echo "Pods:"
kubectl get pods -n $NAMESPACE
echo ""
echo "Services:"
kubectl get svc -n $NAMESPACE
echo ""
echo "ArgoCD Apps:"
kubectl get applications -n argocd

echo ""
echo "🌐 6. Información de acceso:"

# Password ArgoCD
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "No disponible")

echo "📱 ArgoCD UI:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   https://localhost:8080"
echo "   Usuario: admin"
echo "   Password: $ARGOCD_PASSWORD"
echo ""

echo "📱 Aplicación:"
echo "   kubectl port-forward svc/staging-frontend-service-stg -n $NAMESPACE 3000:80"
echo "   http://localhost:3000"
echo ""

echo "🎉 LISTO! Tu aplicación debería estar funcionando"
