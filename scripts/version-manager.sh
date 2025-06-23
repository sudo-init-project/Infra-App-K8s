#!/bin/bash
set -e

#########################################
# GESTOR DE VERSIONES - Ver y cambiar versiones
#########################################

ENVIRONMENT=${1:-staging}
ACTION=${2:-list}
SERVICE=${3}
VERSION=${4}

DOCKER_USER="facundo676"
FRONTEND_REPO="$DOCKER_USER/frontend-shop"
BACKEND_REPO="$DOCKER_USER/backend-shop"

#########################################
# FUNCIONES
#########################################

show_help() {
  echo "🔧 GESTOR DE VERSIONES"
  echo ""
  echo "Uso:"
  echo "  ./version-manager.sh <environment> <action> [service] [version]"
  echo ""
  echo "Acciones:"
  echo "  list                    - Ver todas las versiones"
  echo "  history                 - Ver historial completo"
  echo "  rollback <service> <v#> - Volver a versión anterior"
  echo "  set <service> <v#>      - Cambiar a versión específica"
  echo "  clean                   - Limpiar versiones viejas"
  echo ""
  echo "Ejemplos:"
  echo "  ./version-manager.sh staging list"
  echo "  ./version-manager.sh staging history"
  echo "  ./version-manager.sh staging rollback frontend staging-v1"
  echo "  ./version-manager.sh staging set backend staging-v3"
  echo "  ./version-manager.sh staging clean"
}

# Ver versiones actuales en K8s
show_current_versions() {
  local kustomization_file="overlays/$ENVIRONMENT/kustomization.yaml"
  
  echo "📋 VERSIONES ACTUALES EN $ENVIRONMENT:"
  echo ""
  
  if [ -f "$kustomization_file" ]; then
    echo "🔧 En Kustomization:"
    frontend_version=$(awk "/name: $FRONTEND_REPO/{getline; if(/newTag:/) print \$2}" "$kustomization_file" 2>/dev/null || echo "none")
    backend_version=$(awk "/name: $BACKEND_REPO/{getline; if(/newTag:/) print \$2}" "$kustomization_file" 2>/dev/null || echo "none")
    
    echo "   Frontend: $frontend_version"
    echo "   Backend:  $backend_version"
  else
    echo "❌ No hay archivo kustomization"
  fi
  
  echo ""
  echo "🐳 Imágenes Docker disponibles:"
  
  # Mostrar imágenes frontend
  echo "   Frontend ($FRONTEND_REPO):"
  docker images "$FRONTEND_REPO" --format "      {{.Tag}}\t{{.CreatedAt}}\t{{.Size}}" 2>/dev/null | head -10 || echo "      (no hay imágenes)"
  
  # Mostrar imágenes backend  
  echo "   Backend ($BACKEND_REPO):"
  docker images "$BACKEND_REPO" --format "      {{.Tag}}\t{{.CreatedAt}}\t{{.Size}}" 2>/dev/null | head -10 || echo "      (no hay imágenes)"
  
  echo ""
  echo "☸️ Estado de pods:"
  kubectl get pods -n "proyecto-cloud-$ENVIRONMENT" 2>/dev/null | grep -E "(frontend|backend)" || echo "   (no hay pods)"
}

# Ver historial completo
show_history() {
  local history_file="tags/${ENVIRONMENT}-versions.txt"
  
  echo "📚 HISTORIAL DE VERSIONES - $ENVIRONMENT:"
  echo ""
  
  if [ -f "$history_file" ]; then
    echo "📅 Deploys anteriores:"
    cat "$history_file" | while read line; do
      echo "   $line"
    done
  else
    echo "❌ No hay historial de versiones"
  fi
  
  echo ""
  echo "🐳 Todas las imágenes en Docker Hub:"
  echo "   (Nota: Para ver imágenes remotas, usar: docker search $DOCKER_USER)"
}

# Cambiar a versión específica
change_version() {
  local service=$1
  local new_version=$2
  local kustomization_file="overlays/$ENVIRONMENT/kustomization.yaml"
  
  if [ -z "$service" ] || [ -z "$new_version" ]; then
    echo "❌ Faltan parámetros: service y version"
    show_help
    return 1
  fi
  
  # Validar servicio
  case "$service" in
    frontend|backend)
      ;;
    *)
      echo "❌ Servicio debe ser: frontend o backend"
      return 1
      ;;
  esac
  
  # Verificar que la imagen existe
  local repo_var="${service^^}_REPO"
  local repo=${!repo_var}
  
  echo "🔍 Verificando que existe $repo:$new_version..."
  if ! docker manifest inspect "$repo:$new_version" >/dev/null 2>&1; then
    echo "❌ La imagen $repo:$new_version no existe"
    echo "💡 Imágenes disponibles:"
    docker images "$repo" --format "   {{.Tag}}" 2>/dev/null || echo "   (ninguna)"
    return 1
  fi
  
  echo "✅ Imagen encontrada, actualizando kustomization..."
  
  # Backup
  cp "$kustomization_file" "$kustomization_file.backup"
  
  # Cambiar versión en kustomization
  if [ "$service" = "frontend" ]; then
    sed -i "/name: $FRONTEND_REPO/,/newTag:/ s/newTag: .*/newTag: $new_version/" "$kustomization_file"
  else
    sed -i "/name: $BACKEND_REPO/,/newTag:/ s/newTag: .*/newTag: $new_version/" "$kustomization_file"
  fi
  
  echo "📦 Aplicando cambios..."
  kubectl apply -k "overlays/$ENVIRONMENT/" >/dev/null 2>&1
  
  echo "🔄 Reiniciando deployment..."
  kubectl rollout restart deployment/${ENVIRONMENT}-${service}-${ENVIRONMENT:0:3} -n "proyecto-cloud-$ENVIRONMENT" >/dev/null 2>&1
  kubectl rollout status deployment/${ENVIRONMENT}-${service}-${ENVIRONMENT:0:3} -n "proyecto-cloud-$ENVIRONMENT" --timeout=120s >/dev/null 2>&1
  
  # Registrar cambio
  mkdir -p tags
  echo "$(date '+%Y-%m-%d %H:%M:%S') ROLLBACK ${service}=${new_version}" >> "tags/${ENVIRONMENT}-versions.txt"
  
  echo "✅ $service cambiado a versión $new_version"
  echo ""
  echo "🌐 Verificar en:"
  echo "   kubectl port-forward svc/${ENVIRONMENT}-frontend-service-${ENVIRONMENT:0:3} -n proyecto-cloud-$ENVIRONMENT 3000:80"
}

# Limpiar versiones viejas
clean_versions() {
  echo "🧹 Limpiando versiones viejas..."
  
  # Limpiar imágenes Docker locales (mantener solo últimas 3)
  for repo in "$FRONTEND_REPO" "$BACKEND_REPO"; do
    echo "🗑️ Limpiando $repo..."
    docker images "$repo" --format "{{.ID}}" | tail -n +4 | xargs -r docker rmi -f >/dev/null 2>&1 || true
  done
  
  # Limpiar contenedores parados
  docker container prune -f >/dev/null 2>&1 || true
  
  # Limpiar imágenes sin tag
  docker images --filter "dangling=true" -q | xargs -r docker rmi -f >/dev/null 2>&1 || true
  
  echo "✅ Limpieza completada"
  
  # Mostrar lo que quedó
  echo ""
  echo "📦 Imágenes restantes:"
  docker images | grep -E "($DOCKER_USER|REPOSITORY)" || echo "   (ninguna)"
}

#########################################
# SCRIPT PRINCIPAL
#########################################

case "$ENVIRONMENT" in
  dev|staging|production)
    ;;
  *)
    echo "❌ ENVIRONMENT debe ser: dev, staging, production"
    exit 1
    ;;
esac

case "$ACTION" in
  list)
    show_current_versions
    ;;
  history)
    show_history
    ;;
  rollback|set)
    change_version "$SERVICE" "$VERSION"
    ;;
  clean)
    clean_versions
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    echo "❌ Acción no reconocida: $ACTION"
    show_help
    exit 1
    ;;
esac
