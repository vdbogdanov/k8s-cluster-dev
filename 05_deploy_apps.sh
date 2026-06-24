#!/bin/bash
source .env

helm upgrade --install kite \
  oci://ghcr.io/kite-org/charts/kite \
  --version 0.12.3 \
  --namespace kube-system \
  -f - <<EOF
deploymentStrategy:
  type: Recreate
db:
  type: sqlite
  sqlite:
    persistence:
      pvc:
        enabled: true
        accessModes:
          - ReadWriteOnce
        size: 1Gi
EOF
helm template kite helm/universal --show-only templates/route.yaml \
  --namespace kube-system \
  --set "gateway.host=cluster.${DOMAIN}" \
  --set "gateway.mtls.enabled=true" \
  --set "services[0].name=kite" \
  --set "services[0].ports[0].port=8080" | kubectl apply -f -

helm upgrade --install monitoring \
  oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack \
  --version 86.2.2 \
  --namespace monitoring \
  --create-namespace \
  -f - <<EOF
grafana:
  enabled: true
  defaultDashboardsTimezone: Europe/Moscow
  adminUser: ${GRAFANA_USERNAME}
  adminPassword: ${GRAFANA_PASSWORD}
  persistence:
    enabled: true
    size: 1Gi
prometheus:
  enabled: true
  prometheusSpec:
    retention: 30d
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 10Gi
    additionalScrapeConfigs:
      - job_name: crowdsec
        metrics_path: /metrics
        scheme: http
        static_configs:
        - targets: [crowdsec-service.crowdsec.svc.cluster.local:6060]
EOF
helm template grafana helm/universal --show-only templates/route.yaml \
  --namespace monitoring \
  --set "gateway.host=grafana.${DOMAIN}" \
  --set "gateway.mtls.enabled=true" \
  --set "services[0].name=monitoring-grafana" \
  --set "services[0].ports[0].port=80" | kubectl apply -f -

helm upgrade --install share helm/universal \
  --namespace share \
  --create-namespace \
  --values ./apps/share.yaml \
  --set "gateway.host=share.${DOMAIN}"

helm upgrade --install pasta helm/universal \
  --namespace pasta \
  --create-namespace \
  --values ./apps/pasta.yaml \
  --set "gateway.host=pasta.${DOMAIN}" \
  --set "secrets[0].data.POSTGRES_PASSWORD=${POSTGRES_PASSWORD}"

helm upgrade --install netviz helm/universal \
  --namespace netviz \
  --create-namespace \
  --values ./apps/netviz.yaml \
  --set "gateway.host=netviz.${DOMAIN}"
