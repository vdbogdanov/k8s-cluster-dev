# k8s-cluster-dev

This repository contains a set of helm charts combined using helmfile for easy deployment and management of applications in the k8s cluster. Example usage for k3s.

## Get started

Install k3s:
```
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik" sh -
```

Copy and setup secret file:
```
cp secrets.example.yaml secrets.cluster.yaml
```

Change example domain for ingress resources:
```
sed -i '.bak' '/host:/ s/.example.com/.newdomain.com/' secrets.cluster.yaml
```

If you want to test your domains, I recommend using another stage acme server without limits in `secrets.cluster.yaml`:
```
network:
  tls:
    issuerName: nginx-issuer
    secretName: nginx-tls
    server: https://acme-staging-v02.api.letsencrypt.org/directory
```

To configure ACL for ingress you should add the directive `acl` for site in `secrets.cluster.yaml` (10.42.0.0/16 - default k3s local subnet):
```
- host: k3s.example.com
  ingress:
    name: k3s-proxy
  svc:
    namespace: kubernetes-dashboard
    name: kubernetes-dashboard-kong-proxy
    port: 443
    protocol: HTTPS
  acl:
    - 10.42.0.0/16
```

Create services:
```
helmfile sync
```

## Setup apps

### kubernetes-dashboard

Create user `admin-user` for namespace `kubernetes-dashboard`:
```
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
EOF
```

Give `cluster-admin` role for created user `admin-user`:
```
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF
```

Generate access token for 10 hours:
```
kubectl create token -n kubernetes-dashboard admin-user --duration 10h
```

### marzban

You should change VLESS privateKey, SpiderX and shortIds in `secrets.cluster.yaml`.

Generate VLESS privateKey:
```
kubectl exec <marzban pod> -n <marzban namespace> -- /usr/local/bin/xray x25519
```

Generate VLESS SpiderX:
```
pwgen -A0s 20
```

Generate VLESS shortIds:
```
openssl rand -hex 8
```

Create admin user:
```
kubectl exec -it <marzban pod> -n <marzban namespace> -- /bin/bash
marzban-cli admin create --sudo
```

### grafana

You can change default username/password in `secrets.cluster.yaml`.
