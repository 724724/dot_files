#!/usr/bin/env bash

# One bounded intel_gpu_top sample, flattened into small TSV records for QML.
# SIGINT lets intel_gpu_top close its JSON array cleanly before timeout exits.
json=$(timeout -s INT 1.8 intel_gpu_top -J -s 1000 2>/dev/null || true)
[[ -n "$json" ]] || exit 0

jq -r '
  def number: tonumber? // 0;
  .[-1] as $s |
  ["stats",
    ($s.engines["Render/3D"].busy // 0),
    ($s.engines.Blitter.busy // 0),
    ($s.engines.Video.busy // 0),
    ($s.engines.VideoEnhance.busy // 0),
    ($s.frequency.actual // 0),
    ($s.frequency.requested // 0),
    ($s.power.GPU // 0),
    ($s.rc6.value // 0)
  ] | @tsv,
  (($s.clients // {}) | to_entries | map({
    name: ((.value.name // "Unknown") | gsub("[\\t\\r\\n]"; " ")),
    pid:  (.value.pid | number),
    busy: ([.value["engine-classes"][]?.busy | number] | max // 0),
    mem:  ([.value.memory[]?.resident | number] | add // 0)
  }) | map(select(.busy > 0.05 or .mem > 0)) | sort_by(-.busy) | .[:7][] |
    ["proc", .name, .pid, .busy, .mem] | @tsv)
' <<< "$json" 2>/dev/null
