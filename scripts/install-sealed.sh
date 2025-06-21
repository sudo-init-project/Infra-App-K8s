#!/bin/bash
# Script para instalar Sealed Secrets Controller

echo "🔐 Instalando Sealed Secrets Controller..."

# 1. Instalar Sealed Secrets Controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# 2. Esperar a que el controller esté listo
echo "⏳ Esperando a que Sealed Secrets Controller esté listo..."
kubectl wait --for=condition=available deployment/sealed-secrets-controller -n kube-system --timeout=120s

# 3. Descargar kubeseal CLI (para Linux/Mac)
echo "📥 Descargando kubeseal CLI..."
KUBESEAL_VERSION='0.24.0'
wget "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
tar -xvzf kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
rm kubeseal kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz

echo "✅ Sealed Secrets instalado correctamente"
echo "🔑 Ahora puedes crear secrets seguros con: kubeseal"
