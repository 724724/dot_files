#!/usr/bin/env bash

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/waybar_cpumem_mode"
CPU_FILE="${XDG_RUNTIME_DIR:-/tmp}/waybar_cpu_prev"

case "$1" in
  toggle)
    mode="cpu"
    if [ -f "$STATE_FILE" ]; then
      read -r mode < "$STATE_FILE"
    fi
    if [ "$mode" = "cpu" ]; then
      mode="mem"
    else
      mode="cpu"
    fi
    echo "$mode" > "$STATE_FILE"
    exit 0
    ;;
esac

# 기본 모드: cpu
mode="cpu"
if [ -f "$STATE_FILE" ]; then
  read -r mode < "$STATE_FILE"
fi

if [ "$mode" = "cpu" ]; then
  # CPU 사용률 계산 (두 시점 차이)
  read -r _ user nice system idle _ < /proc/stat
  total=$((user + nice + system + idle))

  if [ -f "$CPU_FILE" ]; then
    read -r prev_total prev_idle < "$CPU_FILE"
    dt=$((total - prev_total))
    di=$((idle - prev_idle))
    if [ "$dt" -gt 0 ]; then
      usage=$(( (100 * (dt - di) + dt / 2) / dt ))
    else
      usage=0
    fi
  else
    usage=0
  fi

  echo "$total $idle" > "$CPU_FILE"
  printf "  %d%%\n" "$usage"
else
  # 메모리 사용률
  mem_total_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
  mem_avail_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
  used_kb=$((mem_total_kb - mem_avail_kb))
  pct=$(( (100 * used_kb + mem_total_kb / 2) / mem_total_kb ))
  printf "  %d%%\n" "$pct"
fi

