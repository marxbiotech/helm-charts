{{/*
Expand the name of the chart.
*/}}
{{- define "pre-hook-job.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
Priority: (1) fullnameOverride if set, (2) release name alone if it already contains the chart name,
(3) otherwise "<release-name>-<chart-name>".
*/}}
{{- define "pre-hook-job.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "pre-hook-job.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "pre-hook-job.labels" -}}
helm.sh/chart: {{ include "pre-hook-job.chart" . }}
{{ include "pre-hook-job.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: pre-hook
{{- end }}

{{/*
Selector labels
*/}}
{{- define "pre-hook-job.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pre-hook-job.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the Job name with hash suffix.
Kubernetes Jobs are immutable — a Job with the same name cannot be updated.
Appending a content hash ensures a new Job is created whenever the migration/task changes,
while identical hashes produce the same name (idempotent).
*/}}
{{- define "pre-hook-job.jobName" -}}
{{- $hash := required "job.hash is required — provide a unique hash representing the Job content" .Values.job.hash | lower | replace "_" "-" }}
{{- $name := printf "%s-%s" (include "pre-hook-job.fullname" .) $hash }}
{{- if gt (len $name) 63 }}
{{- fail (printf "job name '%s' exceeds 63 characters (%d) — use fullnameOverride or a shorter hash to reduce length" $name (len $name)) }}
{{- end }}
{{- $name }}
{{- end }}

