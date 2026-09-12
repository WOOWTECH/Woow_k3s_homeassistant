{{/*
Helper templates for the homeassistant chart.
Resource names, labels and selectors are fixed (not derived from the release
name) to keep the render identical to the pre-Helm chart: homeassistant,
postgres, postgres-secret, homeassistant-config, ha-config, postgres-data.
Phase 1 does not rename anything (no v2 redesign).
*/}}

{{- define "homeassistant.ns" -}}
{{ .Values.namespace.name }}
{{- end -}}

{{/* `annotations:` block with the keep policy, or nothing. */}}
{{- define "homeassistant.keepAnnotations" -}}
{{- if .Values.keepOnUninstall -}}
annotations:
  helm.sh/resource-policy: keep
{{- end -}}
{{- end -}}
