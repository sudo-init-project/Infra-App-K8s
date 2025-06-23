#!/bin/bash
set -e

#########################################
# DEPLOY COMPLETO - Build + Tags + ArgoCD
#########################################

ENVIRONMENT=$1

# VALIDAR QUE SE ESPECIFIQUE AMBIENTE
if [ -z "$ENVIRONMENT" ]; then
  echo "❌ ERROR: Debes especificar el ambiente"
  echo ""
  echo "Uso:"
  echo "  ./deploy-all.sh <ambiente>"
  echo ""
  echo "Ambientes disponibles:"
  echo "  dev         - Desarrollo"
  echo "  staging     - Staging/Testing"
  echo "  production  - Producción"
  echo ""
  echo "Ejemplo:"
  echo "  ./deploy-all.sh staging"
  exit 1
fi

echo "🚀 DEPLOY COMPLETO: $ENVIRONMENT"
echo "================================"

# Validar ambiente
case "$ENVIRONMENT" in
  dev|staging|production)
    PROFILE="minikube-$ENVIRONMENT"
    NAMESPACE="proyecto-cloud-$ENVIRONMENT"
    ;;
  *)
    echo "❌ Usar: ./deploy-all.sh [dev|staging|production]"
    exit 1
    ;;
esac

echo "🟢 Ambiente: $ENVIRONMENT"

# Variables de entorno
export MYSQL_USER="${MYSQL_USER:-appuser}"
export MYSQL_PASSWORD="${MYSQL_PASSWORD:-devpass123}"
export MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-rootpass123}"
export JWT_SECRET="${JWT_SECRET:-GjPEfbM33noYJdEX4fymEken7svn6l81Xtnj9sX7Y7E=}"

# Configuración
DOCKER_USER="facundo676"
FRONTEND_REPO="$DOCKER_USER/frontend-shop"
BACKEND_REPO="$DOCKER_USER/backend-shop"
FRONTEND_DIR="../FrontEnd-Shop"
BACKEND_DIR="../BackEnd-Shop"

#########################################
# FUNCIONES
#########################################

log() {
  echo "$(date '+%H:%M:%S') $1"
}

# Obtener tag actual del archivo
get_file_tag() {
  local service=$1
  local tag_file="overlays/$ENVIRONMENT/${service}-tag.yaml"

  if [ -f "$tag_file" ]; then
    grep "image:" "$tag_file" | awk -F: '{print $3}' || echo "none"
  else
    echo "none"
  fi
}

# Verificar si imagen existe en Docker Hub
image_exists_remote() {
  local image=$1
  docker manifest inspect "$image" >/dev/null 2>&1
}

# Verificar si hay cambios en código
has_code_changes() {
  local directory=$1
  local hash_file="$directory/.build_hash"

  if [ ! -f "$hash_file" ]; then
    return 0  # No hay hash, asumir cambios
  fi

  local old_hash=$(cat "$hash_file" 2>/dev/null || echo "")
  local new_hash=$(find "$directory" -type f \( -name "*.js" -o -name "*.java" -o -name "*.json" -o -name "*.xml" \) -exec md5sum {} \; 2>/dev/null | sort | md5sum | cut -d' ' -f1)

  [ "$old_hash" != "$new_hash" ]
}

# Marcar build completo
mark_build_complete() {
  local directory=$1
  local new_hash=$(find "$directory" -type f \( -name "*.js" -o -name "*.java" -o -name "*.json" -o -name "*.xml" \) -exec md5sum {} \; 2>/dev/null | sort | md5sum | cut -d' ' -f1)
  echo "$new_hash" > "$directory/.build_hash"
}

# Generar siguiente tag
generate_next_tag() {
  local current_tag=$1
  local prefix=""
  local version=""

  if [[ "$current_tag" =~ ^([a-z]+-v)([0-9]+)$ ]]; then
    prefix="${BASH_REMATCH[1]}"
    version="${BASH_REMATCH[2]}"
    next_version=$((version + 1))
    echo "${prefix}${next_version}"
  else
    # Si no tiene formato correcto, generar uno nuevo
    echo "${ENVIRONMENT:0:3}-v1"
  fi
}

# Build imagen si es necesario
build_service() {
  local service=$1
  local directory=$2
  local repo=$3

  log "🔍 Verificando $service..."

  if [ ! -d "$directory" ]; then
    log "❌ Directorio no encontrado: $directory"
    return 1
  fi

  # Obtener tag actual del archivo
  local current_tag=$(get_file_tag "$service")

  if [ "$current_tag" = "none" ]; then
    # No hay tag, generar inicial
    current_tag="${ENVIRONMENT:0:3}-v1"
    log "🔨 Generando tag inicial: $current_tag"
    build_needed=true
  else
    log "📋 Tag actual: $current_tag"

    # Verificar si imagen existe
    if image_exists_remote "$repo:$current_tag"; then
      log "✅ Imagen $repo:$current_tag existe en Docker Hub"

      # Verificar si hay cambios en código
      if has_code_changes "$directory"; then
        log "🔨 Cambios detectados en código, generando nueva versión"
        current_tag=$(generate_next_tag "$current_tag")
        build_needed=true
      else
        log "✅ Sin cambios en código, usando imagen existente"
        build_needed=false
      fi
    else
      log "❌ Imagen $repo:$current_tag NO existe, construyendo..."
      build_needed=true
    fi
  fi

  # Construir si es necesario
  if [ "$build_needed" = "true" ]; then
    log "📦 Construyendo $service:$current_tag..."

    cd "$directory"

    # Build imagen
    if docker build --no-cache -t "$repo:$current_tag" . >/dev/null 2>&1; then
      log "📤 Subiendo $repo:$current_tag..."

      if docker push "$repo:$current_tag" >/dev/null 2>&1; then
        mark_build_complete "."
        log "✅ $service listo: $current_tag"

        # Limpiar imágenes locales viejas
        docker images "$repo" --format "{{.Repository}}:{{.Tag}}" | grep -v ":$current_tag" | head -n -1 | xargs -r docker rmi -f >/dev/null 2>&1 || true

      else
        log "❌ Error al subir $service"
        return 1
      fi
    else
      log "❌ Error al construir $service"
      return 1
    fi

    cd - >/dev/null
  fi

  # Actualizar archivo de tag
  update_tag_file "$service" "$current_tag"
  echo "$current_tag"
}

# Actualizar archivo de tag
update_tag_file() {
  local service=$1
  local tag=$2
  local tag_file="overlays/$ENVIRONMENT/${service}-tag.yaml"

  cat > "$tag_file" << EOF
# ${service^^} VERSION - ${ENVIRONMENT^^}
# Cambiar image tag para actualizar versión

apiVersion: apps/v1
kind: Deployment
metadata:
  name: $service
  namespace: proyecto-cloud
spec:
  template:
    spec:
      containers:
      - name: $service
        image: $DOCKER_USER/${service}-shop:$tag
EOF
}

#########################################
# VERIFICAR MINIKUBE
#########################################
log "🚀 Verificando Minikube..."

if ! minikube status -p "$PROFILE" 2>/dev/null | grep -q "Running"; then
  log "❌ Minikube no está corriendo"
  log "💡 Ejecuta primero:"
  log "   minikube start -p $PROFILE --cpus=4 --memory=4092"
  exit 1
fi

kubectl config use-context "$PROFILE" >/dev/null 2>&1
log "✅ Minikube OK"

#########################################
# BUILD IMÁGENES
#########################################
log ""
log "🔍 ============================================"
log "🔍 VERIFICANDO Y CONSTRUYENDO IMÁGENES"
log "🔍 ============================================"

# Build servicios
FRONTEND_TAG=$(build_service "frontend" "$FRONTEND_DIR" "$FRONTEND_REPO")
BACKEND_TAG=$(build_service "backend" "$BACKEND_DIR" "$BACKEND_REPO")

if [ -z "$FRONTEND_TAG" ] || [ -z "$BACKEND_TAG" ]; then
  log "❌ Error en construcción de imágenes"
  exit 1
fi

log ""
log "📋 Tags finales:"
log "   Frontend: $FRONTEND_REPO:$FRONTEND_TAG"
log "   Backend: $BACKEND_REPO:$BACKEND_TAG"

#########################################
# PREPARAR AMBIENTE
#########################################
log ""
log "🎯 Preparando ambiente..."

# Crear namespace
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1

# Borrar secrets existentes primero
kubectl delete secret mysql-secret app-secret -n "$NAMESPACE" 2>/dev/null || true

# Crear secrets
kubectl create secret generic mysql-secret \
  --from-literal=username="$MYSQL_USER" \
  --from-literal=password="$MYSQL_PASSWORD" \
  --from-literal=root-password="$MYSQL_ROOT_PASSWORD" \
  --namespace="$NAMESPACE" >/dev/null 2>&1

kubectl create secret generic app-secret \
  --from-literal=jwt-secret="$JWT_SECRET" \
  --namespace="$NAMESPACE" >/dev/null 2>&1

log "✅ Secrets creados"

#########################################
# INSTALAR ARGOCD
#########################################
log "🚀 Verificando ArgoCD..."

if ! kubectl get namespace argocd >/dev/null 2>&1; then
  log "🚀 Instalando ArgoCD..."
  kubectl create namespace argocd >/dev/null 2>&1
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml >/dev/null 2>&1

  log "⏳ Esperando ArgoCD..."
  kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s >/dev/null 2>&1

  log "✅ ArgoCD instalado"
else
  log "✅ ArgoCD ya existe"
fi

# Crear/actualizar aplicación ArgoCD
kubectl delete application "proyecto-cloud-$ENVIRONMENT" -n argocd --ignore-not-found=true >/dev/null 2>&1

cat << EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: proyecto-cloud-$ENVIRONMENT
  namespace: argocd
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
EOF

log "✅ ArgoCD aplicación configurada"

#########################################
# DEPLOY
#########################################
log ""
log "📦 Desplegando con Kustomize..."

# Aplicar manifiestos
kubectl apply -k "overlays/$ENVIRONMENT/" 2>&1 | grep -v "Warning.*deprecated" || true

log "✅ Deploy aplicado"

# Forzar restart si se actualizaron las imágenes
log "🔄 Forzando actualización de pods..."
kubectl rollout restart deployment/staging-frontend-stg deployment/staging-backend-stg -n "$NAMESPACE" >/dev/null 2>&1

log "⏳ Esperando pods..."
sleep 30

#########################################
# ESTADO FINAL
#########################################
log ""
log "📋 Estado de pods:"
kubectl get pods -n "$NAMESPACE"

echo ""
echo "🎉 ¡DEPLOY COMPLETADO!"
echo ""
echo "📋 Versiones desplegadas:"
echo "   Frontend: $FRONTEND_REPO:$FRONTEND_TAG"
echo "   Backend: $BACKEND_REPO:$BACKEND_TAG"
echo ""

# ArgoCD info
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "admin")

echo "🌐 ACCESO A ARGOCD:"
echo "   📱 UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   🌍 URL: https://localhost:8080"
echo "   👤 Usuario: admin"
echo "   🔑 Password: $ARGOCD_PASSWORD"
echo ""
echo "🌐 ACCESO A LA APLICACIÓN:"
echo "   📱 Frontend: kubectl port-forward svc/staging-frontend-service-stg -n $NAMESPACE 3000:80"
echo "   🌍 URL: http://localhost:3000"
echo "   👤 Login: admin / admin"
echo ""
echo "🎯 GitOps configurado - ArgoCD sincroniza automáticamente"