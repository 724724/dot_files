#!/usr/bin/env bash

# Return only windows that are visible on each monitor's active workspace.
# CaptureService invokes this once when Window mode opens and after relevant
# Hyprland events; no untrusted title/class text is ever evaluated as shell.

set -u

clients_json="$(/usr/bin/hyprctl clients -j 2>/dev/null || true)"
monitors_json="$(/usr/bin/hyprctl monitors -j 2>/dev/null || true)"
[[ -n "$clients_json" ]] || clients_json='[]'
[[ -n "$monitors_json" ]] || monitors_json='[]'

/usr/bin/jq -cn --argjson clients "$clients_json" --argjson monitors "$monitors_json" '
  [
    $clients[] as $client
    | $monitors[] as $monitor
    | select($monitor.id == $client.monitor)
    | select(($client.mapped // true) == true and ($client.hidden // false) == false)
    | select(
        ($client.pinned // false) == true
        or $client.workspace.id == $monitor.activeWorkspace.id
        or (($monitor.specialWorkspace.id // 0) != 0
            and $client.workspace.id == $monitor.specialWorkspace.id)
      )
    | select(($client.at | type) == "array" and ($client.size | type) == "array")
    | select(($client.size[0] // 0) >= 8 and ($client.size[1] // 0) >= 8)
    | {
        address: ($client.address // ""),
        title: ($client.title // ""),
        class: ($client.class // ""),
        at: $client.at,
        size: $client.size,
        focusHistoryID: ($client.focusHistoryID // 999999),
        monitorName: ($monitor.name // "")
      }
  ]
' 2>/dev/null || printf '[]\n'
