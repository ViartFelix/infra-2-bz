{{- define "planning.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "planning.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "planning.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "planning.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "planning.labels" -}}
helm.sh/chart: {{ include "planning.chart" . }}
{{ include "planning.selectorLabels" . }}
app.kubernetes.io/part-of: devhub-campus
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "planning.selectorLabels" -}}
app.kubernetes.io/name: {{ include "planning.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
