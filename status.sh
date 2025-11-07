#!/bin/bash
# Optimized status script for Flatpak WezTerm

# --- CPU Usage (using /proc/stat) ---
cpu_usage=$(awk '{u=$2+$4; t=$2+$4+$5; if (NR==1){u1=u; t1=t;} else print ($2+$4-u1) * 100 / (t-t1) }' \
  <(grep 'cpu ' /proc/stat) <(sleep 0.1; grep 'cpu ' /proc/stat))

if [ -z "$cpu_usage" ]; then
    cpu_usage="0"
fi
cpu_info=$(printf "󰍛 %.0f%%" "$cpu_usage")

# --- CPU Temperature ---
temp_info=""
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    if [ -n "$temp" ]; then
        temp_c=$((temp / 1000))
        temp_info="󰔏 ${temp_c}°C"
    fi
fi

# --- RAM and Swap (using /proc/meminfo) ---
mem_swap_info=$(awk '
  /^MemTotal:/ {mem_total=$2} 
  /^MemAvailable:/ {mem_avail=$2} 
  /^SwapTotal:/ {swap_total=$2} 
  /^SwapFree:/ {swap_free=$2}
  END {
    if (mem_total > 0) {
      mem_used = mem_total - mem_avail
      mem_pct = int(mem_used * 100 / mem_total)
    } else {
      mem_pct = 0
    }
    
    if (swap_total > 0) {
      swap_used = swap_total - swap_free
      swap_pct = int(swap_used * 100 / swap_total)
    } else {
      swap_pct = 0
    }
    
    printf "󰘚 %d%% | 󰁯 %d%%", mem_pct, swap_pct
  }
' /proc/meminfo)

# --- Battery ---
battery_info=""
if [ -f /sys/class/power_supply/BAT0/capacity ]; then
    charge=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null)
    if [ -n "$charge" ]; then
        battery_info="󰂎 $charge%"
    fi
fi

# --- Output ---
output="$cpu_info"

if [ -n "$temp_info" ]; then
    output="$temp_info | $output"
fi

output="$output | $mem_swap_info"

if [ -n "$battery_info" ]; then
    output="$output | $battery_info"
fi

echo "$output"
