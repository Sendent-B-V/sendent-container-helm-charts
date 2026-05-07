{{/* Expand the name of the chart. */}}
{{- define "sendent-msteams.name" -}}
{{- default .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Create a default fully qualified app name. */}}
{{- define "sendent-msteams.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "sendent-msteams.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}