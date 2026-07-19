{{/*
Expand the name of the chart.
*/}}
{{- define "standalone-job.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "standalone-job.fullname" -}}
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
{{- define "standalone-job.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "standalone-job.selectorLabels" -}}
app.kubernetes.io/name: {{ include "standalone-job.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: standalone-job
{{- end }}

{{/*
Common labels.
*/}}
{{- define "standalone-job.labels" -}}
helm.sh/chart: {{ include "standalone-job.chart" . }}
{{ include "standalone-job.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Create a Job name that is unique for an operator-selected run.
An explicit job.nameOverride takes precedence; otherwise job.runId is appended to
the release-scoped fullname. Names are rejected rather than truncated so the
unique portion can never be silently removed.
*/}}
{{- define "standalone-job.jobName" -}}
{{- $name := .Values.job.nameOverride }}
{{- if not $name }}
{{- $runId := required "job.runId or job.nameOverride is required when job.enabled=true" .Values.job.runId }}
{{- $name = printf "%s-%s" (include "standalone-job.fullname" .) $runId }}
{{- end }}
{{- if gt (len $name) 63 }}
{{- fail (printf "job name '%s' exceeds 63 characters (%d); shorten job.runId, job.nameOverride, or fullnameOverride" $name (len $name)) }}
{{- end }}
{{- $name }}
{{- end }}

{{/*
Create the ServiceAccount name.
*/}}
{{- define "standalone-job.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "standalone-job.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
