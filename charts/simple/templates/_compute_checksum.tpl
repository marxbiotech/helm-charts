{{- define "compute_checksum" -}}
  {{- $subpaths := splitList "/" .path }}
  {{- $data := .Values }}
  {{- range $key, $subpath := $subpaths }}
    {{- /* 路徑打錯時要報錯：否則會當成 null 算出固定的雜湊，之後改設定 pod 也不會重啟 */ -}}
    {{- if not (hasKey $data $subpath) }}
      {{- fail (printf "compute_checksum: %s: missing key %q" $.path $subpath) }}
    {{- end }}
    {{- $data = index $data $subpath }}
  {{- end }}
  {{- /* 字串照原本的算法（既有用法的結果不變）；map、list 等先轉成 JSON（key 已排序）再算 */ -}}
  {{- if kindIs "string" $data }}
    {{- $data | sha256sum }}
  {{- else }}
    {{- $data | toJson | sha256sum }}
  {{- end }}
{{- end -}}
