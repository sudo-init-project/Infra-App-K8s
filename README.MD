# Infra-App-K8s

Infraestructura Kubernetes para aplicación E-Commerce en SpringBoot con GitOps.

## Descripción

Este repositorio contiene los manifiestos de Kubernetes necesarios para desplegar una aplicación e-commerce completa usando Kustomize para gestión multi-entorno y ArgoCD para GitOps.

## Arquitectura

- **Frontend**: React + Nginx
- **Backend**: Spring Boot API 
- **Database**: MySQL con persistencia
- **GitOps**: ArgoCD + Kustomize

## Estructura

```
├── base/                    # Manifiestos base
│   ├── db/                  # MySQL StatefulSet
│   ├── back/                # Backend Deployment
│   ├── front/               # Frontend Deployment
│   ├── namespace.yaml
│   ├── secrets.yaml
│   └── kustomization.yaml
├── overlays/
│   ├── production/          # Configuración producción
│   └── staging/             # Configuración staging
├── argocd-cm.yaml
├── argocd-cmd-params-cm.yaml
└── argocdApp.yaml           # Aplicación ArgoCD
```

## Instalación

### Prerrequisitos

- Kubernetes cluster
- kubectl configurado
- ArgoCD instalado

### Despliegue con ArgoCD

```bash
# Configurar ArgoCD
kubectl apply -f argocd-cm.yaml
kubectl apply -f argocd-cmd-params-cm.yaml

# Crear aplicación
kubectl apply -f argocdApp.yaml
```

### Despliegue manual

```bash
# Staging
kubectl apply -k overlays/staging

# Production
kubectl apply -k overlays/production
```

## Configuración

### Entornos

| Entorno | Réplicas Backend | Réplicas Frontend | Tag Imagen |
|---------|------------------|-------------------|------------|
| Staging | 1 | 1 | latest |
| Production | 3 | 3 | v1.0.0 |

### Secrets requeridos

Crear antes del despliegue:

```yaml
# mysql-secret
MYSQL_ROOT_PASSWORD: <password>
MYSQL_USER: <user>
MYSQL_PASSWORD: <password>

# app-secret  
JWT_SECRET: <jwt-secret>
```

## Verificación

```bash
# Ver pods
kubectl get pods -n proyecto-cloud

# Ver servicios
kubectl get svc -n proyecto-cloud

# Logs del backend
kubectl logs -f deployment/backend-deployment -n proyecto-cloud
```

## Componentes

### Base de Datos
- MySQL StatefulSet con PersistentVolume (10Gi)
- Inicialización automática con ConfigMap
- Headless Service para descubrimiento

### Backend
- Spring Boot API
- Health checks configurados
- Variables de entorno desde Secrets

### Frontend
- React SPA con Nginx
- Proxy reverso al backend
- Archivos estáticos optimizados

## GitOps

La aplicación se sincroniza automáticamente desde este repositorio usando ArgoCD:

- **Repo**: `https://github.com/sudo-init-project/infra-app-k8s`
- **Path**: `overlays/staging` 
- **Auto-sync**: Habilitado
- **Self-heal**: Habilitado

## Troubleshooting

### Pods pendientes
```bash
kubectl describe pod <pod-name> -n proyecto-cloud
```

### Problemas de conectividad DB
```bash
kubectl exec -it <backend-pod> -n proyecto-cloud -- nc -zv mysql-service 3306
```

### Estado ArgoCD
```bash
kubectl get application -n argocd
```

## Repositorios relacionados

- [Database-Shop](https://github.com/sudo-init-project/Database-Shop) - Esquemas SQL
- [FrontEnd-Shop](https://github.com/sudo-init-project/FrontEnd-Shop) - React App  
- [BackEnd-Shop](https://github.com/sudo-init-project/BackEnd-Shop) - Spring Boot API
