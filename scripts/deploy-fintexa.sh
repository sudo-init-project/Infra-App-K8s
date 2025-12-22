#!/bin/bash

# SCRIPT PARA FINTEXA (DEPLOYAR TODO ASI ESTA PREPARADO Y NO TENER QUE HACERLO MANUALMENTE)

# Colores para hacerlo mas pro
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."

echo -e "${BLUE}==========================================================${NC}"
echo -e "${BLUE}       EMPECEMOS CON ESTO FINTEXA-TECNICA-DEVOPS            ${NC}"
echo -e "${BLUE}==========================================================${NC}"

echo -e "${YELLOW}[1/8] Iniciando prerequisitos...${NC}"
command -v docker >/dev/null 2>&1 || { echo -e "${RED}Error: Docker no esta instalado.${NC}"; exit 1; }
command -v minikube >/dev/null 2>&1 || { echo -e "${RED}Error: Minikube no esta instalado.${NC}"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}Error: Kubectl no esta instalado.${NC}"; exit 1; }
echo -e "${GREEN}✔ Herramientas OK.${NC}"

# 2. Iniciar Minikube
# ------------------------------------------------------------------
echo -e "${YELLOW}[2/8] Gestionando Cluster Local...${NC}"
if minikube status | grep -q "Running"; then
    echo -e "${GREEN}✔ Minikube ya está corriendo capo.${NC}"
else
    minikube start --driver=docker --cpus=2 --memory=4096 --addons=ingress
    echo -e "${GREEN}✔ Cluster levantado.${NC}"
fi

echo -e "${YELLOW}[3/8] Vamo creando los Namespaces (dev, test, argocd)...${NC}"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace test --dry-run=client -o yaml | kubectl apply -f -

echo -e "${YELLOW}[4/8] Instalando ArgoCD...${NC}"
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml


echo -e "${YELLOW}      ...Esperando a que se ponga las pilas el server de argocd...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
echo -e "${GREEN}Ya esta el server de argo listo.${NC}"

#Esto era porque estaba dando un error de condicion de carrera se terminaba antes de que se ejecutaran las aplications
echo -e "${YELLOW}[5/8] Esperando a que la API de argo reconozca las 'Applications'...${NC}"

kubectl wait --for condition=established crd/applications.argoproj.io --timeout=60s

sleep 5
echo -e "${GREEN}API de argo listisha para recibir manifiestos.${NC}"

echo -e "${YELLOW}[6/8] Aplicando manifiestos de la carpeta argocd-apps/...${NC}"

if [ -d "$PROJECT_ROOT/argocd-apps" ]; then
    kubectl apply -f "$PROJECT_ROOT/argocd-apps/"
    echo -e "${GREEN}Manifiestos aplicados.${NC}"
else
    echo -e "${RED}ERROR: No encon la carpeta '$PROJECT_ROOT/argocd-apps'.${NC}"
    exit 1
fi

echo -e "${YELLOW}[7/8] Obteniendo password inicial de argo...${NC}"
ARGO_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo -e "${YELLOW}[8/8] Verificando estado de las Apps...${NC}"
echo -e "Las aplicaciones registradas en ArgoCD son:"
kubectl get application -n argocd

echo -e "${BLUE}==========================================================${NC}"
echo -e "${GREEN} TODO LISTO Y SIN UN ERROR ${NC}"
echo -e "${BLUE}==========================================================${NC}"
echo -e "URL:      ${YELLOW}https://localhost:8080${NC}"
echo -e "Usuario:  ${YELLOW}admin${NC}"
echo -e "Password: ${YELLOW}$ARGO_PWD${NC}"
echo -e ""
echo -e "Hace el port-forward en otra terminal para ver la magia de argo:"
echo -e "${YELLOW}kubectl port-forward svc/argocd-server -n argocd 8080:443${NC}"
echo -e "Por Facundo Herrera tomenme en consideracion porfavor :( "