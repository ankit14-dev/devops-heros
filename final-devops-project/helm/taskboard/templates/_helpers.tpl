{{- define "taskboard.fullname" -}}
{{- printf "%s" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "taskboard.labels" -}}
app.kubernetes.io/part-of: taskboard
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "taskboard.selector" -}}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "taskboard.secretName" -}}
{{- if .Values.postgresql.existingSecret -}}
{{ .Values.postgresql.existingSecret }}
{{- else -}}
{{ include "taskboard.fullname" . }}-db
{{- end -}}
{{- end -}}
