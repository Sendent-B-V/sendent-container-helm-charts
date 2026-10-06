# Nextcloud for Outlook Helm Chart

Deploy the Nextcloud for Outlook add-in on Kubernetes.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- A running Nextcloud instance
- A domain name pointing to your cluster (e.g., `outlook.example.com`)

## Installation

Create a file called `my-values.yaml` with your configuration:

```yaml
config:
  BASE_URL: https://outlook.example.com
  DEFAULT_NEXTCLOUD_URL: https://nextcloud.example.com
  MS_AUTH_TYPE: naa_silent
  MS_APP_ID: your-azure-app-id
  MS_TENANT_ID: your-azure-tenant-id
```

Install:

```bash
helm install sendent-outlook ./outlook-addin -f my-values.yaml
```

Verify the deployment is running:

```bash
kubectl get pods -l app.kubernetes.io/name=outlook-addin
```

You should see your pod(s) in `Running` status.

The chart creates a `ClusterIP` service on port 4300. See [Exposing the add-in](#exposing-the-add-in) for how to make it accessible externally.

## Configuration

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `config.BASE_URL` | Public URL where the add-in will be accessible | Yes | `""` |
| `config.DEFAULT_NEXTCLOUD_URL` | Nextcloud server URL. Also the proxy allowlist fallback when `PROXY_ALLOWLIST` is empty | Yes | `""` |
| `config.PROXY_ALLOWLIST` | Comma-separated hostnames or URLs of the Nextcloud servers the add-in may reach through the proxy. When empty, only the `DEFAULT_NEXTCLOUD_URL` host is allowed; when both are empty, the proxy forwards to any server | No | `""` |
| `config.FEATURES_CODES_TO_REMOVE` | Comma-separated feature codes to disable (e.g. `"0,1,2"`). Code `6` (automatic email signature) requires `MS_AUTH_TYPE` `naa_silent`; under any other auth type it is removed at startup with a notice in the log | No | `""` |
| `config.MS_AUTH_TYPE` | Authentication type: `legacy_exchange`, `naa`, or `naa_silent` | No | `"legacy_exchange"` |
| `config.MS_APP_ID` | Azure App ID (required if `MS_AUTH_TYPE` is `naa` or `naa_silent`) | Conditional | `""` |
| `config.MS_TENANT_ID` | Azure Tenant ID (required for non single-tenant apps) | Conditional | `""` |
| `config.PROXY_PLACEHOLDER_URL` | Proxy placeholder URL | No | `"https://placeholder.sendent.dev"` |
| `config.NAA_AUTH_LOG_LEVELS` | Auth log levels: `none`, `all`, or comma-separated (`error`, `debug`, `warning`) | No | `"all"` |

### Deployment Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `1` |
| `image.repository` | Container image repository | `rg.nl-ams.scw.cloud/sendent-public/sendent-outlook` |
| `image.tag` | Container image tag | `"latest"` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.port` | Service port | `4300` |
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

- An ingress controller (e.g. [ingress-nginx](https://kubernetes.github.io/ingress-nginx/))
- [cert-manager](https://cert-manager.io/) (for automatic TLS certificates)

Install them if they are not already present on your cluster:

```bash
# Ingress controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace

# cert-manager
helm repo add jetstack https://charts.jetstack.io
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
    server: https://acme-v02.api.letsencrypt.org/directory
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
    - host: outlook.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: outlook-addin-tls
      hosts:
        - outlook.example.com
```

Adjust `className`, `annotations`, and `tls` to match your cluster's ingress setup.

### Option B: Reverse proxy

If you prefer to manage routing outside of Kubernetes, keep the default `ClusterIP` service and point your existing reverse proxy (e.g., Nginx, Caddy) at the service. You can use `kubectl port-forward` to expose the service locally:

```bash
kubectl port-forward svc/sendent-outlook-outlook-addin 4300:4300
```

Then configure your reverse proxy to forward traffic from your domain to `localhost:4300`.

## Verifying the deployment

Open `https://outlook.example.com/manifest.xml` in your browser. You should see the manifest XML. If this loads correctly, the deployment works and you can proceed to install the add-in in Outlook using this manifest URL.

## Upgrading

```bash
helm upgrade sendent-outlook ./outlook-addin -f my-values.yaml
```

### Upgrading to 3.0.0

- The add-in now only reaches the Nextcloud servers in `config.PROXY_ALLOWLIST`, or the `config.DEFAULT_NEXTCLOUD_URL` host when the allowlist is empty. Add every Nextcloud server your users sign in to before upgrading. Sign-in to any other server fails with "Forbidden: Target URL is not in the allowlist".
- 3.0.0 serves a new manifest: the add-in is renamed to Nextcloud for Outlook and gains the automatic email signature. The manifest you deployed keeps working, but users only get these changes after you redeploy it from `https://outlook.example.com/manifest.xml`. Microsoft 365 can take up to 48 hours to roll it out.

## Uninstalling

```bash
helm uninstall sendent-outlook
```

## Troubleshooting

```bash
# Pod status
kubectl get pods -l app.kubernetes.io/name=outlook-addin

# Pod events and details
kubectl describe pod -l app.kubernetes.io/name=outlook-addin

# Application logs
kubectl logs -l app.kubernetes.io/name=outlook-addin
```

If your pods are in `CrashLoopBackOff`, check the logs for configuration errors. The most common issues are missing `BASE_URL` or authentication configuration parameters. An entry in `PROXY_ALLOWLIST` that is not a valid hostname or URL also stops the pod at startup.

If users see "Forbidden: Target URL is not in the allowlist" when they sign in, their Nextcloud server is missing from `config.PROXY_ALLOWLIST`. The pod logs list the allowed hosts at startup under `PROXY_ALLOWLIST:`.
