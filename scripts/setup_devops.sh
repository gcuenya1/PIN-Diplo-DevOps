#!/bin/bash

# Variables
NAMESPACE_MONITORING="monitoring"
NAMESPACE_GRAFANA="grafana"

# Función para verificar si un comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Función para verificar si un puerto está en uso
is_port_in_use() {
    lsof -i :$1 >/dev/null 2>&1
}

# 1. Instalación de herramientas
echo "🔧 Verificando herramientas necesarias..."

# Detectar SO
OS=$(uname -s)

if [ "$OS" == "Darwin" ]; then
    echo "🖥️ Sistema detectado: macOS"
    command_exists brew || { echo "Homebrew no está instalado. Instálalo primero."; exit 1; }
    command_exists minikube || brew install minikube
    command_exists kubectl || brew install kubectl
    command_exists docker || brew install docker
    command_exists helm || brew install helm
elif [ "$OS" == "Linux" ]; then
    echo "🐧 Sistema detectado: Linux"
    sudo apt update
    command_exists docker || sudo apt install -y docker.io
    command_exists minikube || {
        curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
        sudo install minikube-linux-amd64 /usr/local/bin/minikube
    }
    command_exists kubectl || {
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/
    }
    command_exists helm || curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
    echo "⚠️ Sistema no soportado"
    exit 1
fi

# 2. Iniciar Minikube en segundo plano correctamente
echo "🚀 Verificando Minikube..."
if minikube status >/dev/null 2>&1; then
    echo "✅ Minikube ya está en ejecución."
else
    echo "⏳ Iniciando Minikube en segundo plano..."
    nohup minikube start --driver=docker > minikube.log 2>&1 &
    sleep 5
    echo "⏳ Esperando que Minikube se inicie completamente..."
    while ! minikube status | grep -q "Running"; do
        sleep 5
        echo "⏳ Aún esperando Minikube..."
    done
    echo "✅ Minikube está en ejecución, configurando kubectl..."
    kubectl config use-context minikube
    minikube addons enable metrics-server
    nohup minikube dashboard > dashboard.log 2>&1 &
fi

# 3. Verificar conexión con el clúster
echo "🔍 Verificando conexión con Kubernetes..."
until kubectl get nodes >/dev/null 2>&1; do
    echo "⏳ Esperando que el clúster esté accesible..."
    sleep 5
done

echo "✅ Conexión establecida con Kubernetes."

# 4. Desplegar NGINX
echo "📦 Verificando despliegue de NGINX..."
if kubectl get deployment nginx >/dev/null 2>&1; then
    echo "✅ NGINX ya está desplegado."
else
    kubectl create deployment nginx --image=nginx
    kubectl expose deployment nginx --type=NodePort --port=80
fi
NGINX_URL=$(minikube service nginx --url)
echo "✅ NGINX desplegado en: $NGINX_URL"

# 5. Instalación de Prometheus y Grafana con Persistencia
echo "📊 Instalando Prometheus y Grafana..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

kubectl create namespace $NAMESPACE_MONITORING --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace $NAMESPACE_GRAFANA --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install prometheus prometheus-community/prometheus --namespace $NAMESPACE_MONITORING
helm upgrade --install grafana grafana/grafana \
  --namespace $NAMESPACE_GRAFANA \
  --set service.type=NodePort \
  --set persistence.enabled=true \
  --set persistence.storageClassName="standard" \
  --set persistence.size=10Gi

# 6. Esperar que Grafana y Prometheus estén listos
echo "⏳ Esperando que Prometheus y Grafana estén listos..."
while : ; do
    STATUS_MONITORING=$(kubectl get pods -n $NAMESPACE_MONITORING --no-headers | awk '{print $3}')
    STATUS_GRAFANA=$(kubectl get pods -n $NAMESPACE_GRAFANA --no-headers | awk '{print $3}')
    if [[ ! $STATUS_MONITORING =~ "Pending|ContainerCreating" && ! $STATUS_GRAFANA =~ "Pending|ContainerCreating" ]]; then
        break
    fi
    echo "⏳ Aún esperando que todos los pods estén en Running..."
    sleep 5
done
echo "✅ Prometheus y Grafana están listos."

# 7. Obtener URLs de acceso sin bloquear la terminal
echo "🔑 Obteniendo accesos..."
GRAFANA_URL=$(minikube service -n grafana grafana --url)
PROMETHEUS_URL=$(minikube service -n monitoring prometheus-server --url)

GRAFANA_PASSWORD=$(kubectl get secret --namespace $NAMESPACE_GRAFANA grafana -o jsonpath="{.data.admin-password}" | base64 --decode)

echo "✅ Accede a Grafana en: $GRAFANA_URL"
echo "Usuario: admin"
echo "Contraseña: $GRAFANA_PASSWORD"
echo "✅ Accede a Prometheus en: $PROMETHEUS_URL"

echo "✅ Instalación completa con almacenamiento persistente para Grafana."