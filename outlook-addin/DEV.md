# Helm Chart Development Guide

This documents how to test the Helm chart locally using minikube, including
deploying with a locally built image and exposing the add-in through nginx on a VPS.

## Prerequisites

- minikube, kubectl, helm installed
- Docker installed (for building images)
- nginx with certbot (if exposing via a domain)

## 1. Start Minikube

```bash
minikube start
```

## 2. Build a Local Image

Minikube runs its own container runtime in a VM, so you need to build the image
inside minikube for Kubernetes to find it.

First, make sure the root `.env` file exists (webpack reads `ADDIN_VERSION` from it
during the build). If you only have `.env.example`, copy it:

```bash
cp outlook-addin/.env.example outlook-addin/.env
```

Then from the **parent directory** (containing both `outlook-addin/` and `shared-libraries/`):

```bash
minikube image build -t sendent-outlook:local -f ./outlook-addin/Dockerfile .
```

This can take a few minutes with **no** output. Wait for it to finish.

Verify it worked:

```bash
minikube image ls | grep sendent-outlook
```

You should see `docker.io/library/sendent-outlook:local`.

## 3. Create a Values File

Create `my-values.yaml` with your config (no ingress needed):

```yaml
config:
  BASE_URL: https://your-domain.example.com
  DEFAULT_NEXTCLOUD_URL: https://nextcloud.example.com
  FEATURES_CODES_TO_REMOVE: ""
  MS_AUTH_TYPE: naa
  MS_APP_ID: your-app-id
  MS_TENANT_ID: your-tenant-id
  PROXY_PLACEHOLDER_URL: https://placeholder.sendent.dev
  NAA_AUTH_LOG_LEVELS: all
```

## 4. Install the Chart

Using the local image:

```bash
helm install sendent-outlook ./helm/outlook-addin \
  -f my-values.yaml \
  --set image.repository=sendent-outlook \
  --set image.tag=local \
  --set image.pullPolicy=Never
```

`pullPolicy=Never` tells Kubernetes to use the image already on the node instead
of trying to pull from a registry.

Verify the pod is running:

```bash
kubectl get pods
```

It should show `1/1 Running`. If it shows `CrashLoopBackOff`, check the logs:

```bash
kubectl logs -l app.kubernetes.io/name=outlook-addin
```

## 5. Access the Add-in

### Option A: Port Forwarding (simplest)

```bash
kubectl port-forward svc/sendent-outlook-outlook-addin 4300:4300
```

The add-in is now at `http://localhost:4300`. This command blocks — stop it with `Ctrl+C`.

To run it in the background:

```bash
nohup kubectl port-forward svc/sendent-outlook-outlook-addin 4300:4300 --address=127.0.0.1 > /dev/null 2>&1 &
```

### Option B: Expose via nginx on a VPS

If minikube is running on a VPS and you want to expose the add-in on a domain,
use port-forward (as above) combined with an nginx reverse proxy.

Example nginx config for `outlook-david.sendent.dev`:

```nginx
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name outlook-david.sendent.dev;

    client_max_body_size 0;
    proxy_buffering off;
    proxy_request_buffering off;
    proxy_read_timeout 86400s;

    ssl_certificate /etc/letsencrypt/live/outlook-david.sendent.dev/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/outlook-david.sendent.dev/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        proxy_pass http://127.0.0.1:4300$request_uri;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Port $server_port;
        proxy_set_header X-Forwarded-Scheme $scheme;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Host $host;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        proxy_connect_timeout 90s;
        proxy_send_timeout 90s;
        proxy_read_timeout 90s;
    }
}

server {
    if ($host = outlook-david.sendent.dev) {
        return 301 https://$host$request_uri;
    }

    listen 80;
    listen [::]:80;
    server_name outlook-david.sendent.dev;
    return 301 https://$host$request_uri;
}
```

Important: use `127.0.0.1` in `proxy_pass`, not `localhost`. Nginx can't resolve
`localhost` without a resolver directive and will return 502.

After saving the config:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

## 6. Updating After Code Changes

When you change the add-in code and want to redeploy:

```bash
# Rebuild the image (from parent directory)
minikube image build -t sendent-outlook:local -f ./outlook-addin/Dockerfile .

# Restart the deployment to pick up the new image
kubectl rollout restart deployment sendent-outlook-outlook-addin
```

## 7. Multiple Replicas

To test load balancing across multiple pods:

```bash
helm upgrade sendent-outlook ./helm/outlook-addin \
  -f my-values.yaml \
  --set image.repository=sendent-outlook \
  --set image.tag=local \
  --set image.pullPolicy=Never \
  --set replicaCount=3
```

Stream logs from all pods with the pod name prefixed:

```bash
kubectl logs -l app.kubernetes.io/name=outlook-addin -f --prefix
```

## 8. Useful Commands

```bash
# List helm releases
helm list

# Check release status
helm status sendent-outlook

# View pods
kubectl get pods

# View pod details/events
kubectl describe pod -l app.kubernetes.io/name=outlook-addin

# View logs
kubectl logs -l app.kubernetes.io/name=outlook-addin

# Uninstall
helm uninstall sendent-outlook

# Stop minikube
minikube stop

# Delete minikube entirely
minikube delete
```

## Gotchas

- **minikube is not a production Kubernetes cluster.** It runs in a VM, so networking
  is different. `kubectl port-forward` is the reliable way to access services.
  Customers with real clusters use Ingress instead.

- **`minikube image build` has no log output.** It can look like it's hanging — just
  wait for it to finish. It's building a multi-stage Docker image which takes time.

- **`kubectl port-forward` dies if the pod restarts.** If you upgrade or the pod
  crashes, you'll need to re-run the port-forward command.

- **nginx must use `127.0.0.1`, not `localhost`** in `proxy_pass`. Otherwise you get
  `502 Bad Gateway` with "no resolver defined to resolve localhost" in the error log.
