{{/*
Chart name, truncated/sanitized for use in resource names.
*/}}
{{- define "banking-app.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully qualified app name, incorporating the release name unless it already
contains the chart name.
*/}}
{{- define "banking-app.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "banking-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "banking-app.labels" -}}
helm.sh/chart: {{ include "banking-app.chart" . }}
{{ include "banking-app.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "banking-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "banking-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "banking-app.componentLabels" -}}
{{ include "banking-app.labels" . }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "banking-app.componentSelectorLabels" -}}
{{ include "banking-app.selectorLabels" . }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "banking-app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "banking-app.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Environment variables shared by both the api and consumer containers.
*/}}
{{- define "banking-app.commonEnv" -}}
- name: DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: {{ .databaseSecretName }}
      key: {{ .Values.database.existingSecretKey }}
{{- if .Values.sqs.queueUrl }}
- name: SQS_QUEUE_URL
  value: {{ .Values.sqs.queueUrl | quote }}
{{- end }}
{{- if .Values.sqs.dlqUrl }}
- name: SQS_DLQ_QUEUE_URL
  value: {{ .Values.sqs.dlqUrl | quote }}
{{- end }}
{{- if .Values.aws.region }}
- name: AWS_REGION
  value: {{ .Values.aws.region | quote }}
{{- end }}
{{- if .Values.aws.endpointUrlSqs }}
- name: AWS_ENDPOINT_URL_SQS
  value: {{ .Values.aws.endpointUrlSqs | quote }}
{{- end }}
- name: DB_PING_TIMEOUT_SECONDS
  value: {{ .Values.env.dbPingTimeoutSeconds | quote }}
- name: SHUTDOWN_TIMEOUT_SECONDS
  value: {{ .Values.env.shutdownTimeoutSeconds | quote }}
{{- end -}}

{{/*
Name of the Secret providing DATABASE_URL: the user-supplied existingSecret,
or this chart's own Secret when one wasn't given (see templates/secret.yaml).
*/}}
{{- define "banking-app.databaseSecretName" -}}
{{- if .Values.database.existingSecret -}}
{{- .Values.database.existingSecret -}}
{{- else -}}
{{- printf "%s-db" (include "banking-app.fullname" .) -}}
{{- end -}}
{{- end -}}
