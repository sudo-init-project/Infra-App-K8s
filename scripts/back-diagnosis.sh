#!/bin/bash

echo "🔍 DIAGNÓSTICO RÁPIDO DEL PROBLEMA"
echo "================================="

NAMESPACE="proyecto-cloud-staging"

# 1. Ver logs del backend que está fallando
echo "📋 1. Logs del backend (CrashLoopBackOff):"
kubectl logs -n $NAMESPACE deployment/staging-backend-stg --tail=20
echo ""

# 2. Describir el pod para ver eventos
echo "📋 2. Eventos del pod backend:"
kubectl describe pod -n $NAMESPACE -l app=backend | tail -20
echo ""

# 3. Verificar secrets
echo "📋 3. Verificar secrets:"
kubectl get secrets -n $NAMESPACE
echo ""

# 4. Verificar variables de entorno del backend
echo "📋 4. Variables de entorno del backend:"
kubectl get deployment staging-backend-stg -n $NAMESPACE -o yaml | grep -A 20 "env:"
echo ""

# 5. Verificar conectividad a MySQL
echo "📋 5. Estado de MySQL:"
kubectl logs -n $NAMESPACE staging-mysql-stg-0 --tail=5
echo ""

# 6. Verificar si la base de datos está inicializada
echo "📋 6. Test de conexión a MySQL:"
kubectl exec -n $NAMESPACE staging-mysql-stg-0 -- mysql -u root -prootpass123 -e "SHOW DATABASES;" 2>/dev/null || echo "❌ Error conectando a MySQL"

echo ""
echo "🔍 DIAGNÓSTICO COMPLETADO"
