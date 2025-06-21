#!/bin/bash

echo "🔍 DIAGNÓSTICO ARGOCD - APLICACIONES NO APARECEN"
echo "=================================================="

# 1. Verificar contexto actual
echo "📋 1. Verificando contexto Kubernetes actual:"
kubectl config current-context
kubectl config get-contexts | grep -E "(CURRENT|minikube)"
echo ""

# 2. Verificar que ArgoCD esté corriendo
echo "📋 2. Verificando estado de ArgoCD:"
kubectl get pods -n argocd
echo ""

# 3. Verificar Applications de ArgoCD
echo "📋 3. Verificando Applications de ArgoCD:"
kubectl get applications -n argocd
echo ""

# 4. Verificar si hay errores en las Applications
echo "📋 4. Describiendo Applications (si existen):"
kubectl get applications -n argocd --no-headers | while read line; do
    app_name=$(echo $line | awk '{print $1}')
    echo "--- Describiendo aplicación: $app_name ---"
    kubectl describe application $app_name -n argocd
    echo ""
done

# 5. Verificar namespaces del proyecto
echo "📋 5. Verificando namespaces del proyecto:"
kubectl get namespaces | grep -E "(proyecto-cloud|staging|dev|prod)"
echo ""

# 6. Verificar pods en namespace de staging
echo "📋 6. Verificando pods en proyecto-cloud-staging:"
kubectl get pods -n proyecto-cloud-staging 2>/dev/null || echo "Namespace proyecto-cloud-staging no existe"
echo ""

# 7. Verificar logs de ArgoCD server
echo "📋 7. Últimos logs de ArgoCD Server:"
kubectl logs deployment/argocd-server -n argocd --tail=20
echo ""

# 8. Verificar configuración de ArgoCD
echo "📋 8. Verificando configuración ArgoCD:"
kubectl get configmap argocd-cm -n argocd -o yaml
echo ""

# 9. Verificar el contenido del directorio argocd
echo "📋 9. Verificando archivos ArgoCD locales:"
ls -la argocd/ 2>/dev/null || echo "Directorio argocd/ no encontrado"
echo ""

# 10. Verificar URL del repositorio
echo "📋 10. Información del repositorio:"
git remote -v 2>/dev/null || echo "No estás en un repositorio git"
echo ""

echo "🔍 DIAGNÓSTICO COMPLETADO"
echo "========================"
echo ""
echo "🔧 PRÓXIMOS PASOS SUGERIDOS:"
echo "1. Revisar la salida anterior"
echo "2. Aplicar las aplicaciones de ArgoCD manualmente si no existen"
echo "3. Verificar que los repositorios sean accesibles"
echo "4. Comprobar permisos de ArgoCD"
