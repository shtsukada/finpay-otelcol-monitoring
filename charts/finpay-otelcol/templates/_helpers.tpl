{{- define "finpay.labels" -}}
app.kubernetes.io/part-of: finpay
app.kubernetes.io/managed-by: Helm
{{- end -}}

{{- define "finpay.name" -}}
finpay-otelcol
{{- end -}}
