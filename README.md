# k8s-cluster-dev

This repository contains a set of helm charts for easy deployment and management of applications in the k8s cluster. Example usage for k3s.

## Get started

Create keys and passwords:
```
openssl rand -hex 32
```

Create and change .env file:
```
cp .env.example .env
vi .env
```

Install k3s:
``` curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik" sh -
```

Run cluster setup:
```
for f in 0*.sh; do bash "$f" || break; done
```

## Useful commands

Block IP with crowdsec:
```
kubectl exec -n crowdsec \
  $(kubectl get pods -n crowdsec -l type=lapi -o name) \
  -- cscli decisions add --ip 127.0.0.1 --duration 30m
```

Unblock IP with crowdsec:
```
kubectl exec -n crowdsec \
  $(kubectl get pods -n crowdsec -l type=lapi -o name) \
  -- cscli decisions delete --ip 127.0.0.1
```

Get all crowdsec alerts:
```
kubectl exec -n crowdsec \
  $(kubectl get pods -n crowdsec -l type=lapi -o name) \
  -- cscli alerts list
```

Inspect crowdsec alert:
```
kubectl exec -n crowdsec \
  $(kubectl get pods -n crowdsec -l type=lapi -o name) \
  -- cscli alert inspect 1
```

Delete all crowdsec alerts:
```
kubectl exec -n crowdsec \
  $(kubectl get pods -n crowdsec -l type=lapi -o name) \
  -- cscli alerts delete --all
```

Get all crowdsec decisions:
```
kubectl exec -n crowdsec \
  $(kubectl get pods -n crowdsec -l type=lapi -o name) \
  -- cscli decisions list
```

Delete all crowdsec decisions:
```
kubectl exec -n crowdsec \
  $(kubectl get pods -n crowdsec -l type=lapi -o name) \
  -- cscli decisions delete --all

kubectl rollout restart deployment crowdsec-envoy-bouncer -n envoy-gateway-system
```
