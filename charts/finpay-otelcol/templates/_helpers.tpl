{{- define "finpay.name" -}}
finpay-otelcol
{{- end -}}

{{- define "finpay.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "finpay.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "finpay.labels" -}}
app.kubernetes.io/name: {{ include "finpay.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: finpay
app.kubernetes.io/managed-by: Helm
{{- end -}}
