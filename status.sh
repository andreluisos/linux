#!/bin/bash

# --- CPU Usage (using /proc/stat) ---
cpu_usage=$(awk '{u=$2+$4; t=$2+$4+$5; if (NR==1){u1=u; t1=t;} else print ($2+$4-u1) * 100 / (t-t1) }' \
  <(grep '^cpu ' /proc/stat) <(sleep 0.1; grep '^cpu ' /proc/stat))

if [ -z "$cpu_usage" ]; then
    cpu_usage="0"
fi
cpu_info=$(printf " %.0f%%" "$cpu_usage")

# --- Temp, RAM, and Swap (Single-pass awk) ---
hwmon_file="/sys/class/hwmon/hwmon2/temp1_input"
awk_args="/proc/meminfo"

# Safely append the hwmon file to awk only if it currently exists
[ -f "$hwmon_file" ] && awk_args="/proc/meminfo $hwmon_file"

mem_temp_swap_info=$(awk -v temp_file="$hwmon_file" '
  FILENAME == "/proc/meminfo" {
    if (/MemTotal:/) { ram_total=$2 }
    if (/MemAvailable:/) { ram_available=$2 }
    if (/SwapTotal:/) { swap_total=$2 }
    if (/SwapFree:/) { swap_free=$2 }
    next
  }
  FILENAME == temp_file {
    cpu_temp = $1 / 1000
    has_temp = 1
    next
  }
  END {
    ram_percent = ((ram_total - ram_available) * 100 / ram_total)
    swap_used = swap_total - swap_free
    swap_percent = (swap_total == 0 ? 0 : (swap_used * 100 / swap_total))
    
    if (has_temp) {
        printf " %.0f°C | 󰍛 %.0f%% | 󰓡 %.0f%%", cpu_temp, ram_percent, swap_percent
    } else {
        printf "󰍛 %.0f%% | 󰓡 %.0f%%", ram_percent, swap_percent
    }
  }
' $awk_args)

# --- Battery ---
battery_info=""
if [ -f /sys/class/power_supply/BAT0/capacity ]; then
    charge=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null)
    if [ -n "$charge" ]; then
        battery_info=" | 󰂎 $charge%"
    fi
fi

# --- Output ---
echo "$cpu_info | $mem_temp_swap_info$battery_info"
