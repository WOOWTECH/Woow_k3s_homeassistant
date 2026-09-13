{{/*
Helper templates for the homeassistant chart.
Resource names, labels and selectors are fixed (not derived from the release
name) to keep the render identical to the pre-Helm chart: homeassistant,
postgres, postgres-secret, homeassistant-config, ha-config, postgres-data.
Phase 1 does not rename anything (no v2 redesign).
*/}}

{{- /*
Target namespace. Falls back to the release namespace so that `-n` ALWAYS
controls object placement: a values-file `namespace.name` that silently beat
`-n` is how a rehearsal once wrote Helm ownership annotations onto a live
production Deployment. Set namespace.name only to place objects somewhere
other than the release namespace, and never in an instance-values file.
*/ -}}
{{- define "homeassistant.ns" -}}
{{ .Values.namespace.name | default .Release.Namespace }}
{{- end -}}

{{/* `annotations:` block with the keep policy, or nothing. */}}
{{- define "homeassistant.keepAnnotations" -}}
{{- if .Values.keepOnUninstall -}}
annotations:
  helm.sh/resource-policy: keep
{{- end -}}
{{- end -}}
