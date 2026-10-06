# Helm Charts

This repository contains Helm charts for the Sendent applications.

## Charts

| Chart                             | Description                                                         |
|-----------------------------------|---------------------------------------------------------------------|
| [outlook-addin](./outlook-addin/) | Nextcloud for Outlook - Nextcloud integration for Microsoft Outlook |
| [msteams-addin](./msteams-addin/) | Nextcloud for MS Teams - Nextcloud integration for Microsoft Teams  |

## Usage

```bash
helm install <release-name> ./<chart-name> -f your-values.yaml
```

See each chart's own README for configuration details.
