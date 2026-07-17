{{- define "notif.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "notif.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "notif.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "notif.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "notif.labels" -}}
helm.sh/chart: {{ include "notif.chart" . }}
{{ include "notif.selectorLabels" . }}
app.kubernetes.io/part-of: devhub-campus
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "notif.selectorLabels" -}}
app.kubernetes.io/name: {{ include "notif.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
