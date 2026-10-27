{{/*
Labels on every object. Usage:
  {{- include "uga-vote.labels" (dict "root" $ "component" "vote") | nindent 4 }}
*/}}
{{- define "uga-vote.labels" -}}
{{ include "uga-vote.selectorLabels" . }}
app.kubernetes.io/part-of: uga-vote
app.kubernetes.io/version: {{ .root.Values.image.tag | default .root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version }}
{{- end }}

{{/*
Labels a Service / Deployment uses to find its pods (these never change).
*/}}
{{- define "uga-vote.selectorLabels" -}}
app.kubernetes.io/name: {{ .component }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end }}

{{/*
Image for one of our own services, tagged with the commit SHA.
The install fails with a clear message if no tag was given.
*/}}
{{- define "uga-vote.image" -}}
{{ .root.Values.image.registry }}/{{ .component }}:{{ required "image.tag is required: the commit SHA of the images to deploy" .root.Values.image.tag }}
{{- end }}

{{/*
Pod security settings that pass the "restricted" Pod Security Standard.
Usage: {{- include "uga-vote.podSecurity" (dict "uid" 10001 "gid" 10001) | nindent 6 }}
*/}}
{{- define "uga-vote.podSecurity" -}}
securityContext:
  runAsNonRoot: true
  runAsUser: {{ .uid }}
  runAsGroup: {{ .gid }}
  fsGroup: {{ .gid }}
  seccompProfile:
    type: RuntimeDefault
{{- end }}

{{/*
Container security settings: no privilege escalation, no Linux capabilities.
Usage: {{- include "uga-vote.containerSecurity" (dict "readOnly" true) | nindent 10 }}
*/}}
{{- define "uga-vote.containerSecurity" -}}
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: {{ .readOnly }}
  capabilities:
    drop: ["ALL"]
{{- end }}
