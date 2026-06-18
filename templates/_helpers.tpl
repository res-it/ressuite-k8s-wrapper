{{- define "chart-wrapper.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "chart-wrapper.wicAppLabel" -}}
{{- default "wicplanet-be" (get (index .Values.ressuite "wicplanet-be") "appLabel") -}}
{{- end -}}

{{- define "chart-wrapper.batchAppLabel" -}}
{{- default "batch-watch-be" (get (index .Values.ressuite "batch-watch-be") "appLabel") -}}
{{- end -}}

{{- define "chart-wrapper.dsAppLabel" -}}
{{- default "ds-watch-be" (get (index .Values.ressuite "ds-watch-be") "appLabel") -}}
{{- end -}}

{{- define "chart-wrapper.ressuiteBeAppLabel" -}}
{{- default "ressuite-be" (get (index .Values.ressuite "ressuite-cross-be") "appLabel") -}}
{{- end -}}
