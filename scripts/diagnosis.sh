#!/bin/bash

echo "🔍 DIAGNÓSTICO COMPLETO DEL PROBLEMA"
echo "================================="

NAMESPACE="proyecto-cloud-staging"

echo "📋 1. Verificar sealed secrets en el filesystem:"
ls -la overlays/staging/*sealed-secret* 2>/dev/null || echo "❌ No hay sealed secrets generados"

echo ""
echo "📋 2. Verificar SealedSecret resources en K8s:"
kubectl get sealedsecrets -n $NAMESPACE 2>/dev/null || echo "❌ No hay SealedSecrets en el cluster"

echo ""
echo "📋 3. Verificar controller logs:"
kubectl logs -n kube-system deployment/sealed-secrets-controller --tail=10

echo ""
echo "📋 4. Verificar eventos en el namespace:"
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -10

echo ""
echo "📋 5. Verificar ArgoCD sync status:"
kubectl describe application proyecto-cloud-staging -n argocd | grep -A 10 "Status:"

echo ""
echo "📋 6. Test manual de kubeseal:"
echo "Testing kubeseal connectivity..."
echo "test: dGVzdA==" | kubectl create secret generic test-secret --dry-run=client --from-file=/dev/stdin -o yaml | kubeseal -o yaml --dry-run || echo "❌ kubeseal no funciona"

echo ""
echo "📋 7. Verificar kustomization.yaml:"
echo "Contenido de overlays/staging/kustomization.yaml:"
cat overlays/staging/kustomization.yaml

echo ""
echo "🔍 DIAGNÓSTICO COMPLETADO"
