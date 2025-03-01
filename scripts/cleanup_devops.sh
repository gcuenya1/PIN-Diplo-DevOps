#!/bin/bash

echo "🧹 Eliminando recursos de Minikube..."

# Eliminar Prometheus y Grafana
helm uninstall prometheus --namespace monitoring
kubectl delete ns monitoring

helm uninstall grafana --namespace grafana
kubectl delete ns grafana

# Eliminar NGINX
kubectl delete deployment nginx
kubectl delete service nginx

# Detener y eliminar Minikube
minikube stop
minikube delete

echo "✅ Cleanup completado."

