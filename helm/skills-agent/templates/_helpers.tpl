{{/*
Expand the name of the chart.
*/}}
{{- define "skills-agent.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "skills-agent.fullname" -}}
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
{{- define "skills-agent.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "skills-agent.labels" -}}
helm.sh/chart: {{ include "skills-agent.chart" . }}
{{ include "skills-agent.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "skills-agent.selectorLabels" -}}
app.kubernetes.io/name: {{ include "skills-agent.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Secret name
*/}}
{{- define "skills-agent.secretName" -}}
{{- if .Values.credentials.create }}
{{- include "skills-agent.fullname" . }}-credentials
{{- else }}
{{- .Values.credentials.existingSecretName }}
{{- end }}
{{- end }}

{{/*
Build the command based on agent type
*/}}
{{- define "skills-agent.command" -}}
{{- if eq .Values.agent "claude" }}
- /bin/sh
- -c
- |
  mkdir -p /home/bun/.claude
  cp /secrets/claude-credentials.json /home/bun/.claude/.credentials.json
  chmod 600 /home/bun/.claude/.credentials.json
  cd /workspace
  claude --dangerously-skip-permissions -p "/{{ .Values.skillName }} {{ .Values.prompt }}"
{{- else if eq .Values.agent "codex" }}
- /bin/sh
- -c
- |
  mkdir -p /home/bun/.codex
  cp /secrets/codex-auth.json /home/bun/.codex/auth.json
  chmod 600 /home/bun/.codex/auth.json
  cd /workspace
  codex --dangerously-skip-permissions "${{ .Values.skillName }} {{ .Values.prompt }}"
{{- end }}
{{- end }}
