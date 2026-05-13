# Unofficial Sendent MS Teams Add-in Helm Chart

Deploy the Sendent Microsoft Teams Add-in on Kubernetes.

> **Disclaimer:** This Helm chart is an unofficial community project and is **not** created, maintained, or officially supported by the Sendent company.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- A running Nextcloud instance
- A domain name pointing to your cluster (e.g., `teams.example.com`)

## Installation

Create a file called `my-values.yaml` with your configuration:

```yaml
config:
  BASE_URL: "[https://teams.example.com](https://teams.example.com)"
  MSAPP_TYPE: "your-app-type"
  MSAPP_ID: "your-azure-app-id"
  MSAPP_TENANT_ID: "your-azure-tenant-id"
  DEFAULT_NEXTCLOUD_URL: "[https://nextcloud.example.com](https://nextcloud.example.com)"

secret:
  MSAPP_PASSWORD: "your-secure-password"

```

Install:

```bash
helm install sendent-msteams ./msteams-addin -f my-values.yaml

```

Verify the deployment is running:

```bash
kubectl get pods -l app.kubernetes.io/name=sendent-msteams

```

You should see your pod(s) in `Running` status.

The chart creates a `ClusterIP` service on port 4200. See [Exposing the add-in](https://www.google.com/search?q=%23exposing-the-add-in) for how to make it accessible externally.

## Configuration

### Application Parameters

| Parameter | Description | Default |
| --- | --- | --- |
| `config.BASE_URL` | Public URL where the add-in will be accessible | `"https://teams.yourdomain.com"` |
| `config.DEFAULT_NEXTCLOUD_URL` | Nextcloud server URL | `"https://nextcloud.yourdomain.com"` |
| `config.MSAPP_TYPE` | Type of Microsoft App | `""` |
| `config.MSAPP_ID` | Azure App ID | `"your-app-id"` |
| `config.MSAPP_TENANT_ID` | Azure Tenant ID | `"your-tenant-id"` |
| `secret.MSAPP_PASSWORD` | Azure App Client Secret/Password | `"your-secure-password"` |

### Deployment Parameters

| Parameter | Description | Default |
| --- | --- | --- |
| `replicaCount` | Number of replicas | `1` |
| `image.repository` | Container image repository | `rg.nl-ams.scw.cloud/sendent-public/sendent-msteams` |
| `image.tag` | Container image tag | `"latest"` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.port` | Service port | `4200` |
| `ingress.enabled` | Enable ingress resource | `false` |
| `resources` | CPU/memory resource requests and limits | `{}` |

The add-in is stateless, so it can be scaled horizontally by increasing `replicaCount`. For production deployments, it is recommended to set resource requests and limits:

```yaml
replicaCount: 3

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi

```

## Exposing the add-in

### Option A: Ingress (recommended)

The chart can create an Ingress resource to expose the add-in externally. You will need:

* An ingress controller (e.g. [ingress-nginx](https://kubernetes.github.io/ingress-nginx/))
* [cert-manager](https://cert-manager.io/) (for automatic TLS certificates)

Install them if they are not already present on your cluster:

```bash
# Ingress controller
helm repo add ingress-nginx [https://kubernetes.github.io/ingress-nginx](https://kubernetes.github.io/ingress-nginx)
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace

# cert-manager
helm repo add jetstack [https://charts.jetstack.io](https://charts.jetstack.io)
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true

```

Create a ClusterIssuer for Let's Encrypt:

```yaml
# cluster-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: [https://acme-v02.api.letsencrypt.org/directory](https://acme-v02.api.letsencrypt.org/directory)
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx

```

```bash
kubectl apply -f cluster-issuer.yaml

```

Point your domain's A record at the ingress controller's external IP:

```bash
kubectl get svc -n ingress-nginx

```

Then add the following to your values file:

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: teams.example.com
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls:
    - secretName: msteams-addin-tls
      hosts:
        - teams.example.com

```

Adjust `className`, `annotations`, `pathType`, and `tls` to match your cluster's ingress setup.

### Option B: Reverse proxy

If you prefer to manage routing outside of Kubernetes, keep the default `ClusterIP` service and point your existing reverse proxy (e.g., Nginx, Caddy) at the service. You can use `kubectl port-forward` to expose the service locally:

```bash
kubectl port-forward svc/sendent-msteams-msteams-addin 4200:4200

```

Then configure your reverse proxy to forward traffic from your domain to `localhost:4200`.

## Upgrading

```bash
helm upgrade sendent-msteams ./msteams-addin -f my-values.yaml

```

## Uninstalling

```bash
helm uninstall sendent-msteams

```

## Troubleshooting

```bash
# Pod status
kubectl get pods -l app.kubernetes.io/name=sendent-msteams

# Pod events and details
kubectl describe pod -l app.kubernetes.io/name=sendent-msteams

# Application logs
kubectl logs -l app.kubernetes.io/name=sendent-msteams

```

If your pods are in `CrashLoopBackOff`, check the logs for configuration errors. The most common issues are missing `BASE_URL` or authentication configuration parameters.