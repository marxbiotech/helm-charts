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
app.kubernetes.io/component: standalone-job
{{- end }}

{{/*
Create a deterministic, collision-resistant Job name for an operator-selected run.
An explicit job.name is the readable base and takes precedence; otherwise
job.runId is appended to the release-scoped fullname. The hash covers the
untruncated readable base and the rendered Job/Pod behavior, so immutable spec
changes produce a new name and different long bases cannot collide after
truncation. Only the readable base is truncated; the eight-character hash is
always preserved and the final DNS label is at most 63 characters.
*/}}
{{- define "standalone-job.jobName" -}}
{{- $readableBase := .Values.job.name }}
{{- if not $readableBase }}
{{- $runId := required "job.runId or job.name is required when job.enabled=true" .Values.job.runId }}
{{- $readableBase = printf "%s-%s" (include "standalone-job.fullname" .) $runId }}
{{- end }}
{{- $image := .Values.image | default dict }}
{{- $imageReference := "" }}
{{- if $image.digest }}
{{- $imageReference = printf "%s@%s" $image.repository $image.digest }}
{{- else }}
{{- $imageReference = printf "%s:%s" $image.repository $image.tag }}
{{- end }}
{{- $behavior := dict
      "readableBase" $readableBase
      "jobSpec" (dict
        "backoffLimit" .Values.job.backoffLimit
        "ttlSecondsAfterFinished" .Values.job.ttlSecondsAfterFinished
        "activeDeadlineSeconds" .Values.job.activeDeadlineSeconds)
      "image" $imageReference
      "imagePullPolicy" .Values.imagePullPolicy
      "imagePullSecrets" (.Values.imagePullSecrets | default list)
      "containerName" (include "standalone-job.name" .)
      "command" (.Values.command | default list)
      "args" (.Values.args | default list)
      "env" (.Values.env | default list)
      "envFrom" (.Values.envFrom | default list)
      "resources" (.Values.resources | default dict)
      "restartPolicy" .Values.restartPolicy
      "serviceAccountName" (include "standalone-job.serviceAccountName" .)
      "podSelectorLabels" (include "standalone-job.selectorLabels" .)
      "podAnnotations" (.Values.podAnnotations | default dict)
      "podLabels" (.Values.podLabels | default dict)
      "podSecurityContext" (.Values.podSecurityContext | default dict)
      "securityContext" (.Values.securityContext | default dict)
      "volumes" (.Values.volumes | default list)
      "volumeMounts" (.Values.volumeMounts | default list)
      "nodeSelector" (.Values.nodeSelector | default dict)
      "tolerations" (.Values.tolerations | default list)
      "affinity" (.Values.affinity | default dict)
-}}
{{- $hash := $behavior | toJson | sha256sum | trunc 8 }}
{{- printf "%s-%s" ($readableBase | trunc 54 | trimSuffix "-") $hash }}
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
