#!/bin/bash
set -e

DOCKER_IMAGE="mvpshe/logger-app:latest"

echo "==== Развертывание распределенной системы логирования ===="

echo "1. Сборка Docker образа и отправка на registry..."
docker login
docker build -t $DOCKER_IMAGE .
docker push mvpshe/logger-app:latest

echo "2. Создание ConfigMap..."
kubectl apply -f config.yaml

echo "3. Развертывание тестового Pod..."
kubectl apply -f pod.yaml

echo "4. Ожидание готовности Pod..."
kubectl wait --for=condition=Ready pod/app-pod --timeout=60s

echo "5. Тестирование API тестового Pod..."
kubectl port-forward pod/app-pod 8080:8080 &

curl http://localhost:8080/
curl http://localhost:8080/status
curl -X POST http://localhost:8080/log -d '{"message": "Test log"}'
curl http://localhost:8080/logs

echo "6. Развертывание Deployment с 3 репликами..."
kubectl apply -f deployment.yaml

echo "7. Ожидание готовности Deployment..."
kubectl rollout status deployment/app-deployment

echo "8. Развертывание Service для балансировки нагрузки..."
kubectl apply -f service.yaml

echo "9. Развертывание DaemonSet для сбора логов..."
kubectl apply -f daemonset.yaml

echo "10. Развертывание CronJob для архивирования логов..."
kubectl apply -f cronjob.yaml

echo "==== Система успешно развернута! ===="
echo "Для тестирования выполните:"
echo "  kubectl port-forward svc/app-service 8080:80"
echo "  curl http://localhost:8080/"
echo "  curl http://localhost:8080/status"
echo "  curl -X POST http://localhost:8080/log -d '{\"message\": \"Test log\"}'"
echo "  curl http://localhost:8080/logs"
echo "Для просмотра логов агентов:"
echo "  kubectl logs -l name=log-agent"
echo "Для просмотра результатов архивирования (после срабатывания CronJob):"
echo "  kubectl get pods | grep log-archiver"
echo "  kubectl logs <pod-name>"
