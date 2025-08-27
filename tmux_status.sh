#!/bin/bash
# A script for Fedora 42+ to display CPU usage, CPU temp, RAM usage, swap usage, and battery percentage.
# Requires lm_sensors

# --- CPU Usage ---
cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
cpu_info=$(printf "󰻠 %.0f%%" "$cpu_usage")

# --- CPU Temperature ---
temp_info=""
if command -v sensors >/dev/null 2>&1; then
    # Try to get CPU package temperature first
    temp=$(sensors | grep -i "package id 0" | grep -o "+[0-9]*\.[0-9]*" | head -n1 | sed 's/+//')
    if [ -z "$temp" ]; then
        # Fallback to CPU temp or core temp
        temp=$(sensors | grep -E "(CPU|Tctl|Tccd)" | grep -o "+[0-9]*\.[0-9]*" | head -n1 | sed 's/+//')
    fi
    if [ -n "$temp" ]; then
        temp_info="󰔏 ${temp}°C"
    fi
elif [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    # Fallback to thermal zone
    temp=$(cat /sys/class/thermal/thermal_zone0/temp)
    temp_c=$((temp / 1000))
    temp_info="󰔏 ${temp_c}°C"
fi

# --- RAM and Swap Usage ---
mem_swap_info=$(free | awk '
  /Mem/  { mem=sprintf("󰍛 %.0f%%", $3/$2 * 100) }
  /Swap/ { swap=sprintf("󰁯 %.0f%%", $2>0?$3/$2*100:0) }
  END    { print mem " | " swap }
')

# --- Battery Percentage ---
battery_info=""
batt_dir=$(find /sys/class/power_supply/ -name 'BAT*' | head -n 1)
if [ -n "$batt_dir" ]; then
  charge=$(cat "$batt_dir/capacity")
  status=$(cat "$batt_dir/status")
  battery_info="󰂎 $charge%"
fi

# --- Final Output ---
# Order: CPU USAGE | CPU TEMP | RAM USAGE | SWAP USAGE | BATTERY PERCENTAGE
output="$cpu_info"

if [ -n "$temp_info" ]; then
  output="$temp_info | $output"
fi

output="$output | $mem_swap_info"

if [ -n "$battery_info" ]; then
  output="$output | $battery_info"
fi

echo "$output"
