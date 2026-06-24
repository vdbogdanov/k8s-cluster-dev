#!/bin/bash
source .env

# Wait for cert-manager to be ready
kubectl wait pod \
  --namespace cert-manager --all \
  --for=condition=Ready \
  --timeout=120s

# Install Envoy Gateway
helm upgrade --install envoy \
  oci://docker.io/envoyproxy/gateway-helm \
  --version v1.8.0 \
  --namespace envoy-gateway-system \
  --create-namespace

# Create secret for mTLS CA certificate
kubectl create secret generic mtls-ca-cert \
  --namespace envoy-gateway-system \
  --from-file=ca.crt=pki/ca.crt \
  --dry-run=client -o yaml | kubectl apply -f -

# Create TLS secret for server
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-domain-net
  namespace: envoy-gateway-system
spec:
  secretName: tls-server-cert
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - "*.${DOMAIN}"
  duration: 2160h
  renewBefore: 240h
EOF

# Disable panic threshold globally
kubectl apply -f - <<EOF
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: panic-threshold-override
  namespace: envoy-gateway-system
spec:
  bootstrap:
    type: Merge
    value: |
      layered_runtime:
        layers:
          - name: "disable-panic-threshold"
            static_layer:
              upstream.healthy_panic_threshold: 0
EOF

# Create Envoy GatewayClass
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
  parametersRef:
    group: gateway.envoyproxy.io
    kind: EnvoyProxy
    name: panic-threshold-override
    namespace: envoy-gateway-system
EOF

# Create Envoy Gateway
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: edge-gateway
  namespace: envoy-gateway-system
spec:
  gatewayClassName: envoy
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
    - name: https-public
      protocol: HTTPS
      port: 443
      tls:
        mode: Terminate
        certificateRefs:
          - name: tls-server-cert
      allowedRoutes:
        namespaces:
          from: All
    - name: https-mtls
      protocol: HTTPS
      port: 8443
      tls:
        mode: Terminate
        certificateRefs:
          - name: tls-server-cert
      allowedRoutes:
        namespaces:
          from: All
EOF

# Create Envoy BackendTrafficPolicy for response overrides
kubectl apply -f - <<EOF
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: BackendTrafficPolicy
metadata:
  name: response-override-local
  namespace: envoy-gateway-system
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: edge-gateway
  responseOverride:
    - match:
        statusCodes:
          - type: Range
            range:
              start: 400
              end: 499
      source: Local
      response:
        contentType: text/plain
        body:
          type: Inline
          inline: "Bad request"
    - match:
        statusCodes:
          - type: Range
            range:
              start: 500
              end: 599
      source: Local
      response:
        contentType: text/plain
        body:
          type: Inline
          inline: "Service temporarily unavailable"
EOF

# Create Envoy ClientTrafficPolicy
kubectl apply -f - <<EOF
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: ClientTrafficPolicy
metadata:
  name: mtls-policy
  namespace: envoy-gateway-system
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: edge-gateway
      sectionName: https-mtls
  tls:
    clientValidation:
      caCertificateRefs:
        - name: mtls-ca-cert
EOF

# Create Envoy HTTPRoute
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: https-redirect
  namespace: envoy-gateway-system
spec:
  parentRefs:
    - name: edge-gateway
      sectionName: http
  rules:
    - filters:
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            statusCode: 301
            port: 443
EOF
