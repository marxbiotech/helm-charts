{{- define "compute_checksum" -}}
  {{- $subpaths := splitList "/" .path }}
  {{- $data := .Values }}
  {{- range $key, $subpath := $subpaths }}
    {{- $data = index $data $subpath }}
  {{- end }}
  {{- /* 字串照原本的算法（既有用法的結果不變）；map、list 等先轉成 JSON（key 已排序）再算 */ -}}
  {{- if kindIs "string" $data }}
    {{- $data | sha256sum }}
  {{- else }}
    {{- $data | toJson | sha256sum }}
  {{- end }}
{{- end -}}
