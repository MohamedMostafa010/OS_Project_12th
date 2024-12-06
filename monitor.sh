#!/bin/bash

# Directory to store logs and reports
LOG_DIR="./monitoring_logs"
mkdir -p "$LOG_DIR"

# Ensure D-Bus is initialized
eval $(dbus-launch --sh-syntax)
export DBUS_SESSION_BUS_ADDRESS
export DBUS_SESSION_BUS_PID

# Function to check for critical conditions and trigger alerts
function check_critical_conditions {
  # Define alert thresholds
  CRITICAL_MEMORY_THRESHOLD=80  # Memory usage over 80%
  CRITICAL_CPU_THRESHOLD=90     # CPU usage over 90%
  CRITICAL_TEMP_THRESHOLD=80    # Temperature over 80°C
  CRITICAL_DISK_THRESHOLD=90    # Disk usage over 90%

  # Memory Usage Check
  MEM_USAGE=$(free | grep Mem | while read _ total used _; do echo "$((100 * used / total))"; done)
  if [ "$MEM_USAGE" -gt "$CRITICAL_MEMORY_THRESHOLD" ]; then
    zenity --error --text="ALERT: High Memory Usage ($MEM_USAGE%)"
  fi

  # CPU Usage Check (using mpstat to check CPU utilization)
  CPU_USAGE=$(mpstat 1 1 | grep "Average" | sed 's/.*\s\([0-9.]*\)$/\1/' | while read -r idle; do echo $((100 - idle)); done)
  if [ "$CPU_USAGE" -gt "$CRITICAL_CPU_THRESHOLD" ]; then
    zenity --error --text="ALERT: High CPU Usage ($CPU_USAGE%)"
  fi

  # Disk Usage Check
  DISK_USAGE=$(df / -h | tail -n 1 | sed -E 's/.* ([0-9]+)%/\1/')
  if [ "$DISK_USAGE" -gt "$CRITICAL_DISK_THRESHOLD" ]; then
    zenity --error --text="ALERT: High Disk Usage ($DISK_USAGE%)"
  fi
}

# Function: Monitor System Metrics
function monitor_system {
  TIMESTAMP=$(date "+%Y-%m-%d_%H-%M-%S")
  REPORT_DIR="$LOG_DIR/$TIMESTAMP"
  mkdir -p "$REPORT_DIR"  # Create a directory for the specific report

  # CPU Metrics
  echo "=== CPU Metrics ===" > "$REPORT_DIR/cpu_$TIMESTAMP.log"
  mpstat 1 1 >> "$REPORT_DIR/cpu_$TIMESTAMP.log"
  
  # CPU Temperature (requires lm-sensors)
  echo "=== CPU Temperature ===" >> "$REPORT_DIR/cpu_$TIMESTAMP.log"
  sensors >> "$REPORT_DIR/cpu_$TIMESTAMP.log"
  
  # GPU Metrics
  echo "=== GPU Metrics ===" > "$REPORT_DIR/gpu_$TIMESTAMP.log"
  if command -v lshw >/dev/null 2>&1; then
    lshw -C display >> "$REPORT_DIR/gpu_$TIMESTAMP.log"
  else
    echo "lshw not found. GPU metrics skipped." >> "$REPORT_DIR/gpu_$TIMESTAMP.log"
  fi

  # Memory Metrics
  echo "=== Memory Metrics ===" > "$REPORT_DIR/memory_$TIMESTAMP.log"
  free -h >> "$REPORT_DIR/memory_$TIMESTAMP.log"

  # Disk Usage
  echo "=== Disk Usage ===" > "$REPORT_DIR/disk_$TIMESTAMP.log"
  df -h >> "$REPORT_DIR/disk_$TIMESTAMP.log"
  echo "=== SMART Status ===" >> "$REPORT_DIR/disk_$TIMESTAMP.log"
  smartctl --all /dev/sda >> "$REPORT_DIR/disk_$TIMESTAMP.log" 2>/dev/null

  # Network Statistics
  echo "=== Network Statistics ===" > "$REPORT_DIR/network_$TIMESTAMP.log"
  ifconfig >> "$REPORT_DIR/network_$TIMESTAMP.log"
  ip -s link >> "$REPORT_DIR/network_$TIMESTAMP.log"

  # System Load Metrics
  echo "=== System Load Metrics ===" > "$REPORT_DIR/load_$TIMESTAMP.log"
  uptime >> "$REPORT_DIR/load_$TIMESTAMP.log"

  # Check for critical conditions
  check_critical_conditions

  # Markdown Report
  REPORT_FILE="$REPORT_DIR/report_$TIMESTAMP.md"
  echo "# System Monitoring Report ($TIMESTAMP)" > "$REPORT_FILE"
  for file in "$REPORT_DIR"/*_"$TIMESTAMP".log; do
    SECTION=$(basename "$file" | sed "s/_$TIMESTAMP.log//")
    echo >> "$REPORT_FILE"
    echo "## $SECTION" >> "$REPORT_FILE"
    echo >> "$REPORT_FILE"
    cat "$file" >> "$REPORT_FILE"
  done

  # Convert Markdown to HTML (requires pandoc)
  if command -v pandoc >/dev/null 2>&1; then
    # Specify the CSS file to be included in the HTML
    pandoc "$REPORT_FILE" -o "${REPORT_FILE%.md}.html"
  else
    echo "Pandoc not installed. HTML report not generated." >> "$LOG_DIR/monitoring.log"
  fi

  zenity --info --text="Monitoring completed. Report saved: $REPORT_FILE"
}

# Function: View Reports
function view_reports {
  if [ ! -d "$LOG_DIR" ]; then
    zenity --error --text="No monitoring reports found. Please run the monitoring script first."
    return
  fi

  # Allow selection of files or directories
  SELECTION=$(zenity --file-selection --title="Select a report or folder to view" --filename="$LOG_DIR/")
  if [ -z "$SELECTION" ]; then
    zenity --info --text="No selection made."
    return
  fi

  if [ -d "$SELECTION" ]; then
    # If a directory is selected, prompt to select a file within it
    REPORT=$(zenity --file-selection --title="Select a report to view" --filename="$SELECTION/")
  elif [ -f "$SELECTION" ]; then
    # If a file is selected directly, use it
    REPORT="$SELECTION"
  else
    zenity --error --text="Invalid selection. Please select a valid file or folder."
    return
  fi

  if [ -z "$REPORT" ]; then
    zenity --info --text="No report selected."
    return
  fi

  # Open the selected file
  if [ -f "$REPORT" ]; then
    if [[ "$REPORT" == *.html ]]; then
      # Open HTML file in browser (use --no-sandbox if running as root)
      chromium --no-sandbox "$REPORT" &
    else
      # Open other files in a text viewer
      zenity --text-info --filename="$REPORT" --title="Report Viewer"
    fi
  else
    zenity --error --text="The selected file does not exist or is not a valid file."
  fi
}

# Interactive Dashboard Menu
function interactive_dashboard {
  while true; do
    CHOICE=$(zenity --list --title="System Monitoring Dashboard" \
      --column="Option" --column="Description" \
      "1" "Run System Monitoring" \
      "2" "View Historical Reports" \
      "3" "Exit" \
      --height=400 --width=400)

    case $CHOICE in
      "1") monitor_system ;;
      "2") view_reports ;;
      "3") zenity --info --text="Goodbye!" ; exit ;;
      *) zenity --error --text="Invalid option. Please try again." ;;
    esac
  done
}

# Run Interactive Dashboard
interactive_dashboard
