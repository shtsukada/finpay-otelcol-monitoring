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

{{/*
Return sha256 checksum of otelcol ConfigMap manifest.
Changing config files or values will change this and trigger a rollout.
*/}}
{{- define "finpay.otelcolConfigChecksum" -}}
{{- include (print $.Template.BasePath "/otelcol.configmap.yaml") . | sha256sum -}}
{{- end -}}
