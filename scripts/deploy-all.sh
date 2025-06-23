#!/bin/bash
set -e

#########################################
# ULTIMATE DEPLOYMIUM
#########################################

ENVIRONMENT=$1

# Validacion de ambiente
if [ -z "$ENVIRONMENT" ]; then
  echo "❌ ERROR: Debes especificar el ambiente ahi te pongo unos comandos para que sepas que hacer "
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

echo "DEPLOY COMPLETO: $ENVIRONMENT"
echo "================================"

case "$ENVIRONMENT" in
  dev)
    PROFILE="minikube-dev"
    NAMESPACE="proyecto-cloud-dev"
    ;;
  staging)
    PROFILE="minikube-staging"
    NAMESPACE="proyecto-cloud-staging"
    ;;
  production)
    PROFILE="minikube-production"
    NAMESPACE="proyecto-cloud-production"
    ;;
  *)
    echo "❌ Usar: ./deploy-all.sh [dev|staging|production]"
    exit 1
    ;;
esac

echo "🟢 Ambiente: $ENVIRONMENT"
echo "Perfil Minikube: $PROFILE"

# Variables de entorno
export MYSQL_USER="${MYSQL_USER:-appuser}"
export MYSQL_PASSWORD="${MYSQL_PASSWORD:-devpass123}"
export MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-rootpass123}"
export JWT_SECRET="${JWT_SECRET:-GjPEfbM33noYJdEX4fymEken7svn6l81Xtnj9sX7Y7E=}"

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

# Esto obtiene el tag
get_file_tag() {
  local service=$1
  local tag_file="overlays/$ENVIRONMENT/${service}-tag.yaml"

  if [ -f "$tag_file" ]; then
    grep "image:" "$tag_file" | cut -d: -f3 || echo "none"
  else
    echo "none"
  fi
}

# Esta funcion actualiza los tags dependiendo de que caiga
update_tag_file() {
  local service=$1
  local tag=$2
  local tag_file="overlays/$ENVIRONMENT/${service}-tag.yaml"

  if [ "$service" = "frontend" ]; then
    local repo="$FRONTEND_REPO"
  else
    local repo="$BACKEND_REPO"
  fi

  cat > "$tag_file" << EOF
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
        image: $repo:$tag
EOF

  log "📝 Actualizado $tag_file con tag: $tag"
}

# Esto agarra el tag del deployment actual
get_deployment_tag() {
  local service=$1
  kubectl get deployment "${ENVIRONMENT}-${service}-${ENVIRONMENT:0:3}" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | cut -d: -f2 || echo "none"
}

# Esto verifica si existe la img en docker hub
image_exists_remote() {
  local image=$1
  docker manifest inspect "$image" >/dev/null 2>&1
}

# Esto verifica si la img local existe
image_exists_local() {
  local image=$1
  docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^$image$"
}

# Hay cambios en el codigo?
has_code_changes() {
  local directory=$1
  local hash_file="$directory/.build_hash"

  if [ ! -f "$hash_file" ]; then
    return 0  # No hay hash, no hay na mandamos los cambios
  fi

  local old_hash=$(cat "$hash_file" 2>/dev/null || echo "")
  local new_hash=$(find "$directory" -type f \( -name "*.js" -o -name "*.java" -o -name "*.json" -o -name "*.xml" \) -exec md5sum {} \; 2>/dev/null | sort | md5sum | cut -d' ' -f1)

  [ "$old_hash" != "$new_hash" ]
}


mark_build_complete() {
  local directory=$1
  local new_hash=$(find "$directory" -type f \( -name "*.js" -o -name "*.java" -o -name "*.json" -o -name "*.xml" \) -exec md5sum {} \; 2>/dev/null | sort | md5sum | cut -d' ' -f1)
  echo "$new_hash" > "$directory/.build_hash"
}

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

compare_and_build() {
  local service=$1
  local directory=$2
  local repo=$3

  log "Verificando $service..."

  if [ ! -d "$directory" ]; then
    log "❌ Directorio no encontrado: $directory"
    return 1
  fi

  local file_tag=$(get_file_tag "$service")
  local deployment_tag=$(get_deployment_tag "$service")

  if [ "$file_tag" = "none" ]; then
    # No hay tag en archivo, generar inicial
    file_tag="${ENVIRONMENT:0:3}-v1"
    log "🔨 Generando tag inicial: $file_tag"
    build_needed=true
  elif [ "$deployment_tag" = "none" ]; then
    # No hay deployment, usar tag del archivo
    log "🔨 No hay deployment, usando tag: $file_tag"
    build_needed=true
  elif [ "$file_tag" = "$deployment_tag" ]; then
    # Tags son iguales, verificar cambios en código
    log "📋 Tags iguales (archivo: $file_tag, deployment: $deployment_tag)"

    if has_code_changes "$directory"; then
      log "🔨 Cambios detectados en código, generando nueva versión"
      file_tag=$(generate_next_tag "$file_tag")
      build_needed=true
    else
      log "✅ Sin cambios en código, saltando build"
      build_needed=false
      echo "$file_tag"
      return 0
    fi
  else
    # Tags diferentes, usar el del archivo
    log "Tags diferentes (archivo: $file_tag, deployment: $deployment_tag)"
    log "Usando tag del archivo: $file_tag"

    # Verificar si existe localmente
    if image_exists_local "$repo:$file_tag"; then
      log "✅ Imagen $repo:$file_tag existe localmente, no construyendo"
      build_needed=false
    # Verificar si existe remotamente
    elif image_exists_remote "$repo:$file_tag"; then
      log "📥 Imagen $repo:$file_tag existe remotamente, haciendo pull..."
      if docker pull "$repo:$file_tag" >/dev/null 2>&1; then
        log "✅ Pull completado, no construyendo"
        build_needed=false
      else
        log "❌ Error en pull, construyendo..."
        build_needed=true
      fi
    else
      log "❌ Imagen $repo:$file_tag NO existe, construyendo..."
      build_needed=true
    fi
  fi

  # Construir solo si es necesario
  if [ "$build_needed" = "true" ]; then
    log "📦 Construyendo $service:$file_tag..."

    cd "$directory"

    # Build imagen
    if docker build --no-cache -t "$repo:$file_tag" . >/dev/null 2>&1; then
      log "Subiendo $repo:$file_tag..."

      if docker push "$repo:$file_tag" >/dev/null 2>&1; then
        mark_build_complete "."
        log "✅ Build completado: $file_tag"

        # Actualizar archivo de tag
        cd - >/dev/null
        update_tag_file "$service" "$file_tag"

        echo "$file_tag"
        return 0
      else
        log "❌ Error subiendo imagen"
        cd - >/dev/null
        return 1
      fi
    else
      log "❌ Error construyendo imagen"
      cd - >/dev/null
      return 1
    fi
  else
    log "⏭️ Saltando build para $service"
    echo "$file_tag"
    return 0
  fi
}

#########################################
# VERIFICAR Y CONFIGURAR MINIKUBE
#########################################
log "Verificando y configurando Minikube..."

# Verificar que el perfil existe
if ! minikube profile list | grep -q "$PROFILE"; then
  log "❌ Perfil $PROFILE no existe"
  log "Crealo con:"
  log "   minikube start -p $PROFILE --cpus=4 --memory=4092"
  exit 1
fi

# Verificar que está corriendo
if ! minikube status -p "$PROFILE" 2>/dev/null | grep -q "Running"; then
  log "Minikube $PROFILE no está corriendo"
  log "Inicia con:"
  log "   minikube start -p $PROFILE"
  exit 1
fi

# Cambiar al perfil correcto
log "🔄 Cambiando al perfil: $PROFILE"
minikube profile "$PROFILE" >/dev/null 2>&1

# Configurar kubectl al contexto correcto
kubectl config use-context "$PROFILE" >/dev/null 2>&1

log "✅ Minikube configurado: $PROFILE"
log "📋 Contexto actual: $(kubectl config current-context)"

#########################################
# BUILD IMÁGENES
#########################################
log ""
log "🔍 ============================================"
log "🔍 VERIFICANDO Y CONSTRUYENDO IMÁGENES"
log "🔍 ============================================"

# Build servicios
FRONTEND_TAG=$(compare_and_build "frontend" "$FRONTEND_DIR" "$FRONTEND_REPO")
BACKEND_TAG=$(compare_and_build "backend" "$BACKEND_DIR" "$BACKEND_REPO")

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

#########################################
# ESPERAR PODS
#########################################
log "⏳ Esperando que los pods estén listos..."

log "🔄 Esperando frontend..."
if kubectl rollout status deployment/${ENVIRONMENT}-frontend-${ENVIRONMENT:0:3} -n "$NAMESPACE" --timeout=180s 2>/dev/null; then
  log "✅ Frontend listo"
else
  log "⚠️ Frontend tardó mucho, continuando..."
fi

log "🔄 Esperando backend..."
if kubectl rollout status deployment/${ENVIRONMENT}-backend-${ENVIRONMENT:0:3} -n "$NAMESPACE" --timeout=180s 2>/dev/null; then
  log "✅ Backend listo"
else
  log "⚠️ Backend tardó mucho, continuando..."
fi

log "🔄 Esperando MySQL..."
if kubectl rollout status statefulset/${ENVIRONMENT}-mysql-${ENVIRONMENT:0:3} -n "$NAMESPACE" --timeout=120s 2>/dev/null; then
  log "✅ MySQL listo"
else
  log "⚠️ MySQL tardó mucho, continuando..."
fi

#########################################
# ESTADO FINAL
#########################################
log ""
log "📋 Estado de pods:"
kubectl get pods -n "$NAMESPACE" 2>/dev/null || log "❌ Error obteniendo pods"

log ""
log "📋 Estado de servicios:"
kubectl get svc -n "$NAMESPACE" 2>/dev/null || log "❌ Error obteniendo servicios"

echo ""
echo "🎉 ¡DEPLOY COMPLETADO GIL!"
echo ""
echo "📋 Versiones desplegadas:"
echo "   Frontend: $FRONTEND_REPO:$FRONTEND_TAG"
echo "   Backend: $BACKEND_REPO:$BACKEND_TAG"
echo ""

ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null)

if [ -z "$ARGOCD_PASSWORD" ]; then
  ARGOCD_PASSWORD="admin"
fi

echo "🌐 ACCESO A ARGOCD:"
echo "   UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   URL: https://localhost:8080"
echo "   Usuario: admin"
echo "   Password: $ARGOCD_PASSWORD"
echo ""
echo "🌐 ACCESO A LA APLICACIÓN:"
echo "   Frontend: kubectl port-forward svc/${ENVIRONMENT}-frontend-service-${ENVIRONMENT:0:3} -n $NAMESPACE 3000:80"
echo "   URL: http://localhost:3000"
echo "   Login: admin / admin"
echo ""
echo ""
echo "💡 Para verificar el estado:"
echo "   kubectl get pods -n $NAMESPACE"
echo "   kubectl logs -f deployment/${ENVIRONMENT}-backend-${ENVIRONMENT:0:3} -n $NAMESPACE"
echo ""
echo "Cluster activo: $PROFILE"
echo "Para cambiar manualmente: minikube profile $PROFILE"