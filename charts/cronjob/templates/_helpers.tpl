{{/*
Expand the name of the chart.
*/}}
{{- define "cronjob.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "cronjob.fullname" -}}
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
{{- define "cronjob.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "cronjob.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cronjob.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "cronjob.labels" -}}
helm.sh/chart: {{ include "cronjob.chart" . }}
{{ include "cronjob.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: cronjob
{{- end }}

{{/*
Name of the CronJob object.

Design Decision: unlike the sibling standalone-job chart, this name carries no
behavior hash. A Job's spec.template is immutable, so standalone-job has to
rename itself whenever the run configuration changes. A CronJob is fully
mutable, so a stable name is what allows a schedule, image, or environment
change to be an in-place update instead of a delete-and-recreate that discards
job history and any manual suspend.

Design Decision: truncated to 52, not the usual 63. Kubernetes validates
CronJob names against DNS1035LabelMaxLength minus 11, because each run is named
"<cronjob-name>-<unix-minutes>". A 63-character name passes helm template and
is then rejected by the API server at apply time.
*/}}
{{- define "cronjob.cronJobName" -}}
{{- include "cronjob.fullname" . | trunc 52 | trimSuffix "-" }}
{{- end }}

{{/*
Resolve the container image reference. A digest takes precedence over a tag.
*/}}
{{- define "cronjob.image" -}}
{{- $image := .Values.image | default dict }}
{{- if $image.digest }}
{{- printf "%s@%s" $image.repository $image.digest }}
{{- else }}
{{- printf "%s:%s" $image.repository $image.tag }}
{{- end }}
{{- end }}

{{/*
Create the ServiceAccount name.
*/}}
{{- define "cronjob.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "cronjob.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
