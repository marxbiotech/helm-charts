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

Design Decision: capped at 52, not the usual 63. Kubernetes validates
CronJob names against DNS1035LabelMaxLength minus 11, because each run is named
"<cronjob-name>-<unix-minutes>". A 63-character name passes helm template and
is then rejected by the API server at apply time.

Design Decision: over-length is an error here, not a truncation. Only the
sibling standalone-job chart appends an eight-character behavior hash, which is
what lets it truncate safely: the hash covers the untruncated base, so different
long bases cannot collide after truncation. A stable name cannot carry that
hash, so truncating here would let two releases whose names share a
52-character prefix collapse onto one CronJob, surfacing later as a confusing
Helm ownership conflict rather than at the point of the mistake. An over-length
name is therefore rejected outright. pre-hook-job already applies that same
policy: its hash is caller-supplied and of arbitrary length, so it cannot
truncate safely either and fails over 63 characters. Rejecting also matches the
policy the schema already applies to fullnameOverride.
*/}}
{{- define "cronjob.cronJobName" -}}
{{- $name := include "cronjob.fullname" . }}
{{- if gt (len $name) 52 }}
{{- fail (printf "cronjob: generated CronJob name %q is %d characters, over the 52-character limit. Kubernetes caps CronJob names at DNS1035LabelMaxLength - 11 because each run is named \"<cronjob-name>-<unix-minutes>\". Use a shorter release name, or set fullnameOverride to a name of at most 52 characters." $name (len $name)) }}
{{- end }}
{{- $name }}
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
