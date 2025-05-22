#!/bin/bash

set -e

DOCKER_IMAGE="mvpshe/logger-app:latest"
NAMESPACE=${NAMESPACE:-default}
PROMETHEUS_NS=${PROMETHEUS_NS:-monitoring}
PROMETHEUS_RELEASE=${PROMETHEUS_RELEASE:-prometheus}

echo "==== Развертывание распределенной системы логирования с Istio и Prometheus ===="

echo "--- Настройка Istio service mesh ---"

echo "Установка Istio control plane (профиль demo)..."
istioctl install --set profile=demo -y --namespace istio-system

echo "Ожидание готовности Istio control plane (istiod)..."
kubectl wait --namespace istio-system --for=condition=ready pod -l app=istiod --timeout=300s
echo "Istio control plane готов."

echo "Включение инъекции Istio sidecar для целевого namespace: ${NAMESPACE}"
kubectl label namespace ${NAMESPACE} istio-injection=enabled --overwrite

echo "--- Настройка Prometheus Stack ---"

echo "Добавление Helm репозитория prometheus-community..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo update

echo "Установка kube-prometheus-stack в namespace: ${PROMETHEUS_NS}..."
helm upgrade --install ${PROMETHEUS_RELEASE} prometheus-community/kube-prometheus-stack \
  --create-namespace --namespace ${PROMETHEUS_NS} \
  --set grafana.service.type=LoadBalancer


echo "Ожидание готовности подов Prometheus Stack..."
kubectl wait --namespace ${PROMETHEUS_NS} --for=condition=ready pod -l app.kubernetes.io/instance=${PROMETHEUS_RELEASE} --timeout=600s
echo "Prometheus Stack готов."

echo "--- Сборка Docker образа и отправка на registry (с метриками) ---"

echo "Сборка Docker образа (с метриками) и отправка на registry..."
docker login
docker build -t $DOCKER_IMAGE .
docker push mvpshe/logger-app:latest

echo "--- Развертывание манифестов приложения с инъекцией Istio ---"

echo "Применение ConfigMap..."
kubectl apply -f k8s/config.yaml --namespace ${NAMESPACE}

echo "Применение Deployment и Service..."
kubectl apply -f k8s/deployment.yaml --namespace ${NAMESPACE}
kubectl apply -f k8s/service.yaml --namespace ${NAMESPACE}

echo "Ожидание готовности Deployment..."
kubectl rollout status deployment/app-deployment --namespace ${NAMESPACE}

echo "Применение DaemonSet и CronJob..."
kubectl apply -f k8s/daemonset.yaml --namespace ${NAMESPACE}
kubectl apply -f k8s/cronjob.yaml --namespace ${NAMESPACE}

echo "Ожидание готовности подов приложения..."
kubectl wait --namespace ${NAMESPACE} --for=condition=ready pod -l app=custom-app --timeout=300s
echo "Поды приложения готовы."

echo "--- Применение конфигурации Istio (Gateway, VirtualService, DestinationRule) ---"

echo "Применение конфигурации Istio..."
kubectl apply -f istio-config/gateway.yaml --namespace ${NAMESPACE}
kubectl apply -f istio-config/virtualservice.yaml --namespace ${NAMESPACE}
kubectl apply -f istio-config/app-destinationrule.yaml --namespace ${NAMESPACE}

echo "--- Применение конфигурации Prometheus (ServiceMonitor) ---"

echo "Применение ServiceMonitor для приложения..."
kubectl apply -f prometheus-config/servicemonitor.yaml --namespace ${NAMESPACE}

echo "==== Развертывание завершено! ===="

echo "--- Доступ к системе ---"
echo "Для доступа к приложению через Istio Ingress Gateway, найдите его внешний IP или hostname:"
echo "kubectl get svc istio-ingressgateway -n istio-system"
echo ""
echo "Для доступа к Prometheus UI, найдите внешний IP или hostname сервиса Prometheus (если Service.Type=LoadBalancer/NodePort):"
echo "kubectl get svc ${PROMETHEUS_RELEASE}-kube-prometheus-stack-prometheus -n ${PROMETHEUS_NS}"
echo ""
echo "Для доступа к Grafana UI, найдите внешний IP или hostname сервиса Grafana (если Service.Type=LoadBalancer/NodePort):"
echo "kubectl get svc ${PROMETHEUS_RELEASE}-grafana -n ${PROMETHEUS_NS}"
echo ""
echo "После получения IP/hostname (<INGRESS_HOST_OR_IP_APP>, <INGRESS_HOST_OR_IP_PROM>, <INGRESS_HOST_OR_IP_GRAFANA>), вы можете отправлять запросы:"
echo "curl http://<INGRESS_HOST_OR_IP_APP>/status"
echo "curl -X POST -d '{\"message\": \"Test log for metrics\"}' http://<INGRESS_HOST_OR_IP_APP>/log"
echo ""
echo "В Prometheus UI (<INGRESS_HOST_OR_IP_PROM>) вы сможете запросить метрики, например:"
echo "  istio_requests_total{destination_service=\"app-service.default.svc.cluster.local\"}"
echo "  app_log_requests_total"
echo "  app_log_attempts_total{status=\"success\"}"
echo "  rate(app_request_duration_seconds_sum[5m]) / rate(app_request_duration_seconds_count[5m])"
echo ""
echo "В Grafana UI (<INGRESS_HOST_OR_IP_GRAFANA>) войдите с логином 'admin' и паролем 'prom-operator'."

echo ""
echo "Для просмотра логов агентов:"
echo "  kubectl logs -l name=log-agent -n ${NAMESPACE}"
echo "Для просмотра результатов архивирования (после срабатывания CronJob):"
echo "  kubectl get pods -l job-name=log-archiver -n ${NAMESPACE}"
echo "  kubectl logs <имя_пода_архиватора> -n ${NAMESPACE}"