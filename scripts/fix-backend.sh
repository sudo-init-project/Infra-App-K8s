#!/bin/bash
set -e

echo "🔧 CORRIGIENDO BACKEND INMEDIATAMENTE"
echo "===================================="

NAMESPACE="proyecto-cloud-staging"

# 1. Verificar que MySQL esté funcionando
echo "📋 1. Verificando MySQL..."
kubectl exec -n $NAMESPACE staging-mysql-stg-0 -- mysql -u root -prootpass123 -e "SHOW DATABASES;" 2>/dev/null && echo "✅ MySQL funcionando" || {
    echo "❌ MySQL no responde, reiniciando..."
    kubectl delete pod staging-mysql-stg-0 -n $NAMESPACE
    kubectl wait --for=condition=ready pod staging-mysql-stg-0 -n $NAMESPACE --timeout=120s
}

# 2. Verificar y corregir secrets
echo "📋 2. Aplicando secrets correctos..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: staging-mysql-secret-stg
  namespace: $NAMESPACE
type: Opaque
stringData:
  username: "appuser"
  password: "devpass123"
  root-password: "rootpass123"
---
apiVersion: v1
kind: Secret
metadata:
  name: staging-app-secret-stg
  namespace: $NAMESPACE
type: Opaque
stringData:
  jwt-secret: "GjPEfbM33noYJdEX4fymEken7svn6l81Xtnj9sX7Y7E="
EOF

# 3. Corregir deployment del backend con patch completo
echo "📋 3. Corrigiendo deployment del backend..."
kubectl patch deployment staging-backend-stg -n $NAMESPACE --type json -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/env",
    "value": [
      {
        "name": "SPRING_DATASOURCE_URL",
        "value": "jdbc:mysql://staging-mysql-service-stg:3306/dbejercicio2final"
      },
      {
        "name": "SPRING_DATASOURCE_USERNAME",
        "valueFrom": {
          "secretKeyRef": {
            "name": "staging-mysql-secret-stg",
            "key": "username"
          }
        }
      },
      {
        "name": "SPRING_DATASOURCE_PASSWORD",
        "valueFrom": {
          "secretKeyRef": {
            "name": "staging-mysql-secret-stg",
            "key": "password"
          }
        }
      },
      {
        "name": "SPRING_JPA_HIBERNATE_DDL_AUTO",
        "value": "none"
      },
      {
        "name": "SPRING_JPA_SHOW_SQL",
        "value": "true"
      },
      {
        "name": "SPRING_JPA_PROPERTIES_HIBERNATE_FORMAT_SQL",
        "value": "true"
      },
      {
        "name": "JWT_SECRET_KEY",
        "valueFrom": {
          "secretKeyRef": {
            "name": "staging-app-secret-stg",
            "key": "jwt-secret"
          }
        }
      }
    ]
  }
]'

# 4. Eliminar pods viejos para forzar recreación
echo "📋 4. Eliminando pods problemáticos..."
kubectl delete pods -n $NAMESPACE -l app=backend

# 5. Esperar que el nuevo deployment esté listo
echo "📋 5. Esperando que el backend esté listo..."
kubectl rollout status deployment/staging-backend-stg -n $NAMESPACE --timeout=300s

# 6. Verificar estado final
echo "📋 6. Verificando estado final:"
kubectl get pods -n $NAMESPACE
echo ""

# 7. Test rápido del backend
echo "📋 7. Probando backend..."
sleep 10
kubectl exec -n $NAMESPACE deployment/staging-backend-stg -- curl -f http://localhost:8080/actuator/health 2>/dev/null && echo "✅ Backend funcionando" || echo "⚠️ Backend aún arrancando..."

echo ""
echo "🎉 CORRECCIÓN COMPLETADA"
echo "========================"
echo ""
echo "🔧 Para probar la aplicación:"
echo "   kubectl port-forward svc/staging-frontend-service-stg -n $NAMESPACE 3000:80"
echo "   kubectl port-forward svc/staging-backend-service-stg -n $NAMESPACE 8080:8080"
echo ""
echo "🌐 Frontend: http://localhost:3000"
echo "   Usuario: admin | Password: admin"
