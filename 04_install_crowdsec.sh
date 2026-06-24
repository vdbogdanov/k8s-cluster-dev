#!/bin/bash
source .env

# Wait for envoy-gateway-system to be ready
kubectl wait pod \
  --namespace envoy-gateway-system \
  --selector 'app.kubernetes.io/name in (envoy,gateway-helm)' \
  --for=condition=Ready \
  --timeout=120s

# Create crowdsec namespace
kubectl create namespace crowdsec --dry-run=client -o yaml | kubectl apply -f -

# Create secret for CrowdSec bouncer key in the crowdsec namespace
kubectl create secret generic crowdsec-bouncer-key \
  --namespace crowdsec \
  --from-literal=BOUNCER_KEY_envoy="${CROWDSEC_BOUNCER_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Install CrowdSec
helm repo add crowdsec https://crowdsecurity.github.io/helm-charts
helm upgrade --install crowdsec crowdsec/crowdsec \
  --namespace crowdsec \
  --create-namespace \
  -f - <<'EOF'
container_runtime: containerd
config:
  config.yaml.local: |
    api:
      client:
        unregister_on_exit: true
      server:
        auto_registration:
          enabled: true
          token: "${REGISTRATION_TOKEN}"
          allowed_ranges:
            - "127.0.0.1/32"
            - "192.168.0.0/16"
            - "10.0.0.0/8"
            - "172.16.0.0/12"
    db_config:
      flush:
        agents_autodelete:
          login_password: 10m
lapi:
  enabled: true
  resources:
    requests:
      cpu: 250m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
  env:
    - name: BOUNCER_KEY_envoy
      valueFrom:
        secretKeyRef:
          name: crowdsec-bouncer-key
          key: BOUNCER_KEY_envoy
agent:
  enabled: true
  enabled: true
  resources:
    requests:
      cpu: 250m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 256Mi
  acquisition:
    - namespace: envoy-gateway-system
      podName: envoy-envoy-gateway-system-edge-gateway-*
      program: envoy
      poll_without_inotify: true
  env:
    - name: COLLECTIONS
      value: "yanis-kouidri/envoy"
appsec:
  enabled: true
  resources:
    requests:
      cpu: 250m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 256Mi
  acquisitions:
    - appsec_configs:
        - crowdsecurity/appsec-default
        - crowdsecurity/crs-inband
        - custom/crs-exclusions
      labels:
        type: appsec
      listen_addr: 0.0.0.0:7422
      path: /
      source: appsec
  env:
    - name: COLLECTIONS
      value: "crowdsecurity/appsec-virtual-patching crowdsecurity/appsec-generic-rules crowdsecurity/appsec-crs-inband"
    - name: SCENARIOS
      value: "crowdsecurity/crowdsec-appsec-inband"
  configs:
    crs-exclusions.yaml: |
      name: custom/crs-exclusions
      on_load:
        - apply:
            - RemoveInBandRuleByID(911100)
            - RemoveInBandRuleByID(920420)
EOF

# Create secret for CrowdSec bouncer key in the envoy-gateway-system namespace
kubectl create secret generic crowdsec-bouncer-key \
  --namespace envoy-gateway-system \
  --from-literal=BOUNCER_KEY_envoy="${CROWDSEC_BOUNCER_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Install the CrowdSec Envoy bouncer
helm upgrade --install crowdsec-envoy-bouncer \
  oci://ghcr.io/kdwils/charts/envoy-proxy-bouncer \
  --version 0.6.1 \
  --namespace envoy-gateway-system \
  -f - <<EOF
fullnameOverride: crowdsec-envoy-bouncer
config:
  bouncer:
    enabled: true
    banStatusCode: 404
    lapiURL: http://crowdsec-service.crowdsec.svc.cluster.local:8080
    apiKeySecretRef:
      name: crowdsec-bouncer-key
      key: BOUNCER_KEY_envoy
  waf:
    enabled: true
    appSecURL: http://crowdsec-appsec-service.crowdsec.svc.cluster.local:7422
    apiKeySecretRef:
      name: crowdsec-bouncer-key
      key: BOUNCER_KEY_envoy
  templates:
    showDeniedPage: false
EOF

# Restart bouncer to pick up the new secret
kubectl rollout restart deployment/crowdsec-envoy-bouncer \
  --namespace envoy-gateway-system

# Create a SecurityPolicy to use the CrowdSec Envoy bouncer
kubectl apply -f - <<EOF
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: crowdsec-ext-auth
  namespace: envoy-gateway-system
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: edge-gateway
  extAuth:
    failOpen: false
    grpc:
      backendRefs:
        - group: ""
          kind: Service
          name: crowdsec-envoy-bouncer
          namespace: envoy-gateway-system
          port: 8080
EOF
