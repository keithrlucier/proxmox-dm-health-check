#!/bin/bash
# VERSION 26 - Proxmox Device Mapper Analysis and Cleanup Script
# Analyzes device mapper entries and provides optional interactive cleanup
# Includes HTML email reporting via Mailjet API

# Mailjet Configuration
MAILJET_API_KEY="%API KEY HERE%"
MAILJET_API_SECRET="%API SECRET HERE%"
FROM_EMAIL="%FROM EMAIL HERE"
FROM_NAME="ProxMox DMSetup Health Check"
TO_EMAIL="%TO EMAIL HERE%"

echo "Proxmox Device Mapper Analysis and Cleanup Tool"
echo "Node: $(hostname)"
echo "Date: $(date)"
echo "Mode: ANALYSIS + OPTIONAL CLEANUP + EMAIL REPORTING"
echo ""

# Get running VMs (suppress any config errors)
echo "Running VMs on this node:"
RUNNING_VMS=$(qm list 2>/dev/null | grep running | awk '{print $1}')
if [ -z "$RUNNING_VMS" ]; then
    echo "   No VMs are currently running"
    RUNNING_VMS=""
else
    echo "   $(echo $RUNNING_VMS | tr '\n' ' ')"
fi
echo ""

# Get device mapper entries for VMs
echo "Device mapper entries analysis:"
DM_ENTRIES=$(dmsetup ls 2>/dev/null | grep -E 'vm--[0-9]+--disk')

if [ -z "$DM_ENTRIES" ]; then
    echo "   No VM device mapper entries found"
    echo ""
    echo "Status: CLEAN - No device mapper entries to analyze"
    # Set default values instead of exiting
    STALE_COUNT=0
    VALID_COUNT=0
    TOTAL_ENTRIES=0
else
    STALE_COUNT=0
    VALID_COUNT=0

    # Create temp file to avoid subshell issues
    TEMP_FILE=$(mktemp)
    echo "$DM_ENTRIES" > "$TEMP_FILE"

    # Analyze each device mapper entry
    while IFS= read -r dm_line; do
        DM_NAME=$(echo "$dm_line" | awk '{print $1}')
        
        # Extract VM ID
        VM_ID=$(echo "$DM_NAME" | sed -n 's/.*vm--\([0-9]\+\)--.*/\1/p')
        
        if [ -z "$VM_ID" ]; then
            echo "UNKNOWN: $DM_NAME (could not parse VM ID)"
            continue
        fi
        
        # Check if this VM is running
        VM_IS_RUNNING=false
        for running_vm in $RUNNING_VMS; do
            if [ "$running_vm" = "$VM_ID" ]; then
                VM_IS_RUNNING=true
                break
            fi
        done
        
        if [ "$VM_IS_RUNNING" = "true" ]; then
            echo "OK: $DM_NAME (VM $VM_ID is running)"
            VALID_COUNT=$((VALID_COUNT + 1))
        else
            echo "STALE: $DM_NAME (VM $VM_ID is not running)"
            STALE_COUNT=$((STALE_COUNT + 1))
        fi
    done < "$TEMP_FILE"

    # Summary
    echo ""
    echo "Summary:"
    TOTAL_ENTRIES=$((VALID_COUNT + STALE_COUNT))
    echo "   Total device mapper entries: $TOTAL_ENTRIES"
    echo "   Valid entries: $VALID_COUNT"
    echo "   Stale entries: $STALE_COUNT"

    if [ "$STALE_COUNT" -eq 0 ]; then
        echo ""
        echo "Status: CLEAN - All device mapper entries are valid"
    else
        echo ""
        echo "Status: ATTENTION - $STALE_COUNT stale device mapper entries detected"
        echo "Recommendation: Review stale entries above"
    fi

    # Show VM to Disk mappings for running VMs
    if [ "$VALID_COUNT" -gt 0 ]; then
        echo ""
        echo "Valid VM to Disk Mappings:"
        
        # Show disks for each running VM
        for vm_id in $(echo $RUNNING_VMS | tr ' ' '\n' | sort -n); do
            echo "   VM $vm_id:"
            
            # Find all device mapper entries for this VM
            while IFS= read -r dm_line; do
                DM_NAME=$(echo "$dm_line" | awk '{print $1}')
                ENTRY_VM_ID=$(echo "$DM_NAME" | sed -n 's/.*vm--\([0-9]\+\)--.*/\1/p')
                
                if [ "$ENTRY_VM_ID" = "$vm_id" ]; then
                    echo "     $DM_NAME"
                fi
            done < "$TEMP_FILE"
        done
    fi
fi

echo ""
echo "Analysis completed - no changes made during analysis phase"

# Gather system metrics for email report AFTER we have STALE_COUNT
echo ""
echo "Gathering system metrics for report..."
HOST_UPTIME=$(uptime -p | sed 's/up //')
HOST_LOAD=$(uptime | awk -F'load average:' '{print $2}' | xargs)
HOST_CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
HOST_CPU_CORES=$(nproc)
HOST_TOTAL_RAM=$(free -h | awk '/^Mem:/ {print $2}')
HOST_USED_RAM=$(free -h | awk '/^Mem:/ {print $3}')
HOST_RAM_PERCENT=$(free | awk '/^Mem:/ {printf "%.1f", $3/$2 * 100}')
HOST_PROXMOX_VERSION=$(pveversion -v | grep "pve-manager" | awk '{print $2}')
HOST_KERNEL=$(uname -r)

# Get CPU usage - handle different top formats
HOST_CPU_USAGE=$(top -bn1 | grep -i "cpu" | grep -v "PID" | head -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /[0-9.]+%/) {gsub("%","",$i); print $i; exit}}')
# If empty or invalid, try alternative method
if [ -z "$HOST_CPU_USAGE" ] || ! [[ "$HOST_CPU_USAGE" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    HOST_CPU_USAGE=$(top -bn1 | awk '/^%Cpu/ {print $2}' | cut -d'%' -f1)
fi
# If still empty, try mpstat
if [ -z "$HOST_CPU_USAGE" ] || ! [[ "$HOST_CPU_USAGE" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    if command -v mpstat >/dev/null 2>&1; then
        HOST_CPU_USAGE=$(mpstat 1 1 | awk '/Average/ {print 100 - $NF}')
    else
        HOST_CPU_USAGE="0"
    fi
fi

# Ensure numeric values for comparisons
HOST_CPU_USAGE=$(echo "$HOST_CPU_USAGE" | cut -d. -f1)
HOST_RAM_PERCENT=$(echo "$HOST_RAM_PERCENT" | cut -d. -f1)
[ -z "$HOST_CPU_USAGE" ] && HOST_CPU_USAGE="0"
[ -z "$HOST_RAM_PERCENT" ] && HOST_RAM_PERCENT="0"

HOST_TOTAL_VMS=$(qm list 2>/dev/null | grep -v VMID | wc -l)
HOST_STOPPED_VMS=$(qm list 2>/dev/null | grep stopped | wc -l)
HOST_CPU_TEMP=""
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    if command -v bc >/dev/null 2>&1; then
        TEMP_C=$(echo "scale=1; $(cat /sys/class/thermal/thermal_zone0/temp)/1000" | bc)
    else
        TEMP_C=$(($(cat /sys/class/thermal/thermal_zone0/temp)/1000))
    fi
    HOST_CPU_TEMP="${TEMP_C}°C"
fi
HOST_SYSTEM_MODEL=$(dmidecode -s system-product-name 2>/dev/null || echo "Unknown")
HOST_BOOT_TIME=$(who -b | awk '{print $3, $4}')

# Get storage usage for main partitions
HOST_ROOT_USAGE=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')
HOST_VAR_USAGE=$(df -h /var 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}' || echo "N/A")

# Get ZFS pool status if available
HOST_ZFS_STATUS=""
if command -v zpool >/dev/null 2>&1; then
    HOST_ZFS_STATUS=$(zpool list -H -o name,health,size,alloc,free 2>/dev/null | head -1 || echo "")
fi

# Get cluster status
HOST_CLUSTER_STATUS="Standalone"
HOST_CLUSTER_NODES=""
if pvecm status >/dev/null 2>&1; then
    HOST_CLUSTER_STATUS="Cluster Member"
    HOST_CLUSTER_NODES=$(pvecm nodes 2>/dev/null | grep -v "Membership" | wc -l)
fi

# Get network interface with most traffic
HOST_PRIMARY_NET=$(ip -s link | awk '/^[0-9]+:/ {iface=$2} /RX:/{getline; rx=$1} /TX:/{getline; tx=$1; total=rx+tx; if(total>max && iface!="lo:"){max=total; primary=iface; primary_rx=rx; primary_tx=tx}} END{gsub(/:$/,"",primary); print primary}')
HOST_NET_IP=$(ip -4 addr show $HOST_PRIMARY_NET 2>/dev/null | grep inet | awk '{print $2}' | head -1 || echo "N/A")

# Get SWAP usage
HOST_SWAP_TOTAL=$(free -h | awk '/^Swap:/ {print $2}')
HOST_SWAP_USED=$(free -h | awk '/^Swap:/ {print $3}')
if [ "$HOST_SWAP_TOTAL" != "0B" ]; then
    HOST_SWAP_PERCENT=$(free | awk '/^Swap:/ {printf "%.1f", $3/$2 * 100}')
    HOST_SWAP_INFO="$HOST_SWAP_USED / $HOST_SWAP_TOTAL (${HOST_SWAP_PERCENT}%)"
else
    HOST_SWAP_INFO="No swap configured"
fi

# Get LVM info if available
HOST_LVM_VGS=""
if command -v vgs >/dev/null 2>&1; then
    HOST_LVM_VGS=$(vgs --noheadings --units g -o vg_name,vg_size,vg_free 2>/dev/null | head -3 | tr '\n' ';' | sed 's/;$//')
fi

# Get container (LXC) count
HOST_TOTAL_CTS=$(pct list 2>/dev/null | grep -v VMID | wc -l)
HOST_RUNNING_CTS=$(pct list 2>/dev/null | grep running | wc -l)

# Get top 3 processes by CPU
HOST_TOP_PROCS=$(ps aux --sort=-%cpu | head -4 | tail -3 | awk '{printf "%.1f%% %s\n", $3, $11}' | tr '\n' ';' | sed 's/;$//')

# Calculate performance grade NOW that we have STALE_COUNT
PERF_SCORE=100
# Ensure we have valid numeric values
if [[ "$HOST_CPU_USAGE" =~ ^[0-9]+$ ]]; then
    # Deduct points for high resource usage
    [ "$HOST_CPU_USAGE" -gt 80 ] && PERF_SCORE=$((PERF_SCORE - 20))
    [ "$HOST_CPU_USAGE" -gt 60 ] && [ "$HOST_CPU_USAGE" -le 80 ] && PERF_SCORE=$((PERF_SCORE - 10))
fi
if [[ "$HOST_RAM_PERCENT" =~ ^[0-9]+$ ]]; then
    [ "$HOST_RAM_PERCENT" -gt 90 ] && PERF_SCORE=$((PERF_SCORE - 20))
    [ "$HOST_RAM_PERCENT" -gt 75 ] && [ "$HOST_RAM_PERCENT" -le 90 ] && PERF_SCORE=$((PERF_SCORE - 10))
fi
# Deduct for stale entries
[ $STALE_COUNT -gt 50 ] && PERF_SCORE=$((PERF_SCORE - 20))
[ $STALE_COUNT -gt 10 ] && [ $STALE_COUNT -le 50 ] && PERF_SCORE=$((PERF_SCORE - 10))

# Assign grade
if [ $PERF_SCORE -ge 90 ]; then
    PERF_GRADE="A+"
    PERF_COLOR="#28a745"
elif [ $PERF_SCORE -ge 80 ]; then
    PERF_GRADE="A"
    PERF_COLOR="#28a745"
elif [ $PERF_SCORE -ge 70 ]; then
    PERF_GRADE="B"
    PERF_COLOR="#17a2b8"
elif [ $PERF_SCORE -ge 60 ]; then
    PERF_GRADE="C"
    PERF_COLOR="#ffc107"
else
    PERF_GRADE="D"
    PERF_COLOR="#dc3545"
fi

echo "System metrics collected."

# Function to generate HTML email report - Professional Clean Design
generate_html_email() {
    local status_color=""
    local status_text=""
    local status_bg_color=""
    
    # Determine overall status
    if [ "$STALE_COUNT" -eq 0 ]; then
        status_color="#155724"
        status_bg_color="#d4edda"
        status_text="HEALTHY"
    elif [ "$STALE_COUNT" -lt 10 ]; then
        status_color="#856404"
        status_bg_color="#fff3cd"
        status_text="WARNING"
    else
        status_color="#721c24"
        status_bg_color="#f8d7da"
        status_text="UN-HEALTHY"
    fi
    
    # Color coding for metrics
    cpu_color="#495057"
    ram_color="#495057"
    load_color="#495057"
    
    # CPU usage color
    if [[ "$HOST_CPU_USAGE" =~ ^[0-9]+$ ]]; then
        if [ "$HOST_CPU_USAGE" -gt 80 ]; then
            cpu_color="#dc3545"
        elif [ "$HOST_CPU_USAGE" -gt 60 ]; then
            cpu_color="#ffc107"
        else
            cpu_color="#28a745"
        fi
    fi
    
    # RAM usage color
    if [[ "$HOST_RAM_PERCENT" =~ ^[0-9]+$ ]]; then
        if [ "$HOST_RAM_PERCENT" -gt 90 ]; then
            ram_color="#dc3545"
        elif [ "$HOST_RAM_PERCENT" -gt 75 ]; then
            ram_color="#ffc107"
        else
            ram_color="#28a745"
        fi
    fi
    
    # Load average color
    load_1min=$(echo "$HOST_LOAD" | awk '{print $1}' | tr -d ',' | cut -d. -f1)
    load_threshold=$((HOST_CPU_CORES * 150 / 100))
    if [ -n "$load_1min" ] && [[ "$load_1min" =~ ^[0-9]+$ ]]; then
        if [ "$load_1min" -gt "$load_threshold" ]; then
            load_color="#dc3545"
        elif [ "$load_1min" -gt "$HOST_CPU_CORES" ]; then
            load_color="#ffc107"
        else
            load_color="#28a745"
        fi
    fi
    
    cat << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset='UTF-8'>
    <meta name='viewport' content='width=device-width, initial-scale=1.0'>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 20px; background-color: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background-color: #fff; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); padding: 25px; }
        .title-header { background-color: #4f46e5; color: white; padding: 20px; border-radius: 6px; margin-bottom: 20px; text-align: center; }
        .section-header { background-color: #4f46e5; color: white; padding: 15px; border-radius: 6px; margin: 20px 0 15px 0; text-align: center; }
        h1 { margin: 0; font-size: 24px; font-weight: bold; }
        h3 { margin: 0; font-size: 18px; font-weight: bold; }
        .summary { background-color: #f8f9fa; padding: 20px; border-radius: 6px; border-left: 4px solid #3498db; margin: 15px 0; }
        .alert { background-color: #fff3cd; color: #856404; padding: 15px; border-radius: 6px; border-left: 4px solid #ffc107; margin: 15px 0; }
        .success { background-color: #d4edda; color: #155724; padding: 15px; border-radius: 6px; border-left: 4px solid #28a745; margin: 15px 0; }
        .disclaimer { font-size: 0.9em; color: #6c757d; margin-bottom: 20px; border-bottom: 1px solid #dee2e6; padding-bottom: 10px; }
        .metric-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 15px; margin: 15px 0; }
        .metric-item { background-color: #f8f9fa; padding: 15px; border-radius: 6px; border: 1px solid #dee2e6; }
        .metric-label { font-weight: bold; color: #495057; margin-bottom: 5px; }
        .metric-value { color: #212529; font-size: 1.1em; }
        .section { margin: 20px 0; padding: 15px; background-color: #f9f9f9; border-radius: 6px; border: 1px solid #dee2e6; }
        .footer { margin-top: 20px; padding-top: 20px; border-top: 1px solid #dee2e6; color: #6c757d; font-size: 0.9em; }
        .vm-section { background-color: #f8f9fa; padding: 15px; border-radius: 6px; border: 1px solid #dee2e6; margin: 10px 0; }
        .vm-title { font-weight: bold; color: #2980b9; margin-bottom: 10px; }
        .vm-disks { background-color: #fff; padding: 10px; border-radius: 4px; font-family: 'Courier New', monospace; font-size: 0.9em; color: #495057; }
        .info-text { font-size: 0.9em; color: #666; margin: 10px 0; }
        .code { background-color: #e9ecef; color: #212529; padding: 2px 4px; border-radius: 3px; font-family: 'Courier New', monospace; font-size: 0.9em; }
        @media screen and (max-width: 600px) {
            .container { padding: 15px; }
            .metric-grid { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
    <div class='container'>
        <div class='disclaimer'>
EOF
    echo "            <p>Proxmox Device Mapper Health Check Report v26 - $(date '+%Y-%m-%d %H:%M:%S')</p>"
    echo "        </div>"
    echo "        "
    echo "        <div class='title-header'>"
    echo "            <h1>$(hostname) - Proxmox Health Report</h1>"
    echo "            <p style='margin: 10px 0 0 0; font-size: 14px; opacity: 0.9;'>Performance Grade: <strong>$PERF_GRADE</strong></p>"
    echo "        </div>"
    echo "        "
    
    if [ "$STALE_COUNT" -gt 0 ]; then
        echo "        <div class='alert' style='background-color: $status_bg_color; color: $status_color; border-left-color: $([ "$STALE_COUNT" -lt 10 ] && echo "#ffc107" || echo "#dc3545");'>"
        echo "            <strong>⚠️ ATTENTION:</strong> $STALE_COUNT DM Setup table stale entries detected - Review recommended"
        echo "            <p class='info-text'>Stale device mapper entries are local access paths to VM disks that remain after VMs have been migrated or shut down. They consume system resources and can cause \"Device or resource busy\" errors. They are safe to remove - the actual VM disk data is NOT affected. To clean up: SSH into $(hostname), run <span class='code'>./ProsourceProx-stale-dm.sh</span> and choose the interactive cleanup option.</p>"
        echo "        </div>"
    else
        echo "        <div class='success'>"
        echo "            <strong>✅ HEALTHY:</strong> All device mapper entries are valid"
        echo "        </div>"
    fi
    
    cat << 'EOF'
        
        <div class='section-header'>
            <h3>📊 Device Mapper Statistics</h3>
        </div>
        
        <div class='section'>
            <div class='metric-grid'>
                <div class='metric-item'>
                    <div class='metric-label'>Total Entries</div>
EOF
    echo "                    <div class='metric-value'>$TOTAL_ENTRIES</div>"
    cat << 'EOF'
                </div>
                <div class='metric-item'>
                    <div class='metric-label'>Valid Entries</div>
EOF
    echo "                    <div class='metric-value' style='color: #28a745;'>$VALID_COUNT</div>"
    cat << 'EOF'
                </div>
                <div class='metric-item'>
                    <div class='metric-label'>DM Setup Table Stale Entries</div>
EOF
    echo "                    <div class='metric-value' style='color: $([ "$STALE_COUNT" -eq 0 ] && echo "#28a745" || echo "#dc3545");'>$STALE_COUNT</div>"
    cat << 'EOF'
                </div>
                <div class='metric-item'>
                    <div class='metric-label'>Running VMs</div>
EOF
    echo "                    <div class='metric-value' style='color: #17a2b8;'>$(echo $RUNNING_VMS | wc -w)</div>"
    cat << 'EOF'
                </div>
            </div>
        </div>
        
        <div class='section-header'>
            <h3>🖥️ Host Information</h3>
        </div>
        
        <div class='section'>
            <div class='metric-grid'>
                <div class='metric-item'>
                    <div class='metric-label'>Proxmox Version</div>
EOF
    echo "                    <div class='metric-value'>$HOST_PROXMOX_VERSION</div>"
    echo "                </div>"
    echo "                <div class='metric-item'>"
    echo "                    <div class='metric-label'>Kernel</div>"
    echo "                    <div class='metric-value'>$HOST_KERNEL</div>"
    echo "                </div>"
    echo "                <div class='metric-item'>"
    echo "                    <div class='metric-label'>Uptime</div>"
    echo "                    <div class='metric-value'>$HOST_UPTIME</div>"
    echo "                </div>"
    echo "                <div class='metric-item'>"
    echo "                    <div class='metric-label'>System Model</div>"
    echo "                    <div class='metric-value'>$HOST_SYSTEM_MODEL</div>"
    echo "                </div>"
    echo "                <div class='metric-item'>"
    echo "                    <div class='metric-label'>CPU Usage</div>"
    echo "                    <div class='metric-value' style='color: $cpu_color;'>${HOST_CPU_USAGE}%$([ -n "$HOST_CPU_TEMP" ] && echo " @ $HOST_CPU_TEMP" || echo "")</div>"
    echo "                </div>"
    echo "                <div class='metric-item'>"
    echo "                    <div class='metric-label'>RAM Usage</div>"
    echo "                    <div class='metric-value' style='color: $ram_color;'>$HOST_USED_RAM / $HOST_TOTAL_RAM (${HOST_RAM_PERCENT}%)</div>"
    echo "                </div>"
    echo "                <div class='metric-item'>"
    echo "                    <div class='metric-label'>Load Average</div>"
    echo "                    <div class='metric-value' style='color: $load_color;'>$HOST_LOAD</div>"
    echo "                </div>"
    echo "                <div class='metric-item'>"
    echo "                    <div class='metric-label'>Virtual Machines</div>"
    echo "                    <div class='metric-value'>$HOST_TOTAL_VMS total ($(echo $RUNNING_VMS | wc -w) running)</div>"
    echo "                </div>"
    echo "                <div class='metric-item'>"
    echo "                    <div class='metric-label'>Containers</div>"
    echo "                    <div class='metric-value'>$HOST_TOTAL_CTS total ($HOST_RUNNING_CTS running)</div>"
    echo "                </div>"
    echo "                <div class='metric-item'>"
    echo "                    <div class='metric-label'>Storage Usage</div>"
    echo "                    <div class='metric-value'>$HOST_ROOT_USAGE</div>"
    echo "                </div>"
    echo "                <div class='metric-item'>"
    echo "                    <div class='metric-label'>Network Interface</div>"
    echo "                    <div class='metric-value'>$HOST_PRIMARY_NET ($HOST_NET_IP)</div>"
    echo "                </div>"
    
    if [ -n "$HOST_TOP_PROCS" ]; then
        echo "                <div class='metric-item'>"
        echo "                    <div class='metric-label'>Top Processes</div>"
        echo "                    <div class='metric-value' style='font-family: Courier New, monospace; font-size: 0.9em;'>$(echo "$HOST_TOP_PROCS" | sed 's/;/<br\/>/g')</div>"
        echo "                </div>"
    fi
    
    echo "            </div>"
    echo "        </div>"

    # Add running VMs section if any exist
    if [ "$VALID_COUNT" -gt 0 ]; then
        echo "        <div class='section-header'>"
        echo "            <h3>🖥️ Running VMs and Their Disks</h3>"
        echo "        </div>"
        echo "        <div class='section'>"
        
        # Show disks for each running VM
        for vm_id in $(echo $RUNNING_VMS | tr ' ' '\n' | sort -n); do
            echo "            <div class='vm-section'>"
            echo "                <div class='vm-title'>💻 Virtual Machine $vm_id</div>"
            echo "                <div class='vm-disks'>"
            
            # Find all device mapper entries for this VM
            while IFS= read -r dm_line; do
                DM_NAME=$(echo "$dm_line" | awk '{print $1}')
                ENTRY_VM_ID=$(echo "$DM_NAME" | sed -n 's/.*vm--\([0-9]\+\)--.*/\1/p')
                
                if [ "$ENTRY_VM_ID" = "$vm_id" ]; then
                    echo "💾 $DM_NAME<br/>"
                fi
            done < "$TEMP_FILE"
            
            echo "                </div>"
            echo "            </div>"
        done
        
        echo "        </div>"
    fi
    
    # Add stale entries warning if any exist
    if [ "$STALE_COUNT" -gt 0 ]; then
        cat << 'EOF'
        <div class='section'>
            <div class='alert'>
EOF
        echo "                <h3 style='margin: 0 0 15px 0; color: $status_color;'>⚠️ Action Required</h3>"
        echo "                <p><strong>$STALE_COUNT DM Setup table stale entries detected.</strong></p>"
        cat << 'EOF'
                <p>These entries are for VMs not running on this node and should be cleaned up to prevent "Device or resource busy" errors.</p>
                <p><strong>Recommended Action:</strong> Run the interactive cleanup script on this node during next maintenance window.</p>
                <p><strong>Command:</strong> <code style='background-color: #f8f9fa; padding: 2px 4px; border-radius: 4px; font-family: Courier New, monospace;'>./ProsourceProx-stale-dm.sh</code> and choose interactive cleanup option.</p>
            </div>
        </div>
EOF
    else
        cat << 'EOF'
        <div class='section'>
            <div class='success'>
                <h3 style='margin: 0 0 15px 0; color: #155724;'>✅ System Status: Healthy</h3>
                <p>No DM Setup table stale entries found. All device mapper entries are for VMs currently running on this node.</p>
            </div>
        </div>
EOF
    fi
    
    echo "        <div class='footer'>"
    echo "            <p><strong>ProxMox DMSetup Health Check v26</strong></p>"
    echo "            <p>Node: <strong>$(hostname)</strong> • Generated: $(date)</p>"
    echo "        </div>"
    echo "    </div>"
    echo "</body>"
    echo "</html>"
}

# Function to send email via Mailjet
send_mailjet_email() {
    local html_content="$1"
    local subject="$2"
    
    # Escape HTML for JSON (basic escaping)
    local html_escaped=$(echo "$html_content" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr '\n' ' ')
    
    # Create JSON payload
    local json_payload="{\"Messages\":[{\"From\":{\"Email\":\"$FROM_EMAIL\",\"Name\":\"$FROM_NAME\"},\"To\":[{\"Email\":\"$TO_EMAIL\"}],\"Subject\":\"$subject\",\"HTMLPart\":\"$html_escaped\",\"TextPart\":\"Proxmox Device Mapper Report for $(hostname) - $STALE_COUNT stale entries found. Please view in HTML format for full details.\"}]}"
    
    # Send email via Mailjet API
    local response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -u "$MAILJET_API_KEY:$MAILJET_API_SECRET" \
        -d "$json_payload" \
        "https://api.mailjet.com/v3.1/send")
    
    # Check response
    if echo "$response" | grep -q '"Status":"success"'; then
        echo "✅ Email report sent successfully to $TO_EMAIL"
        return 0
    else
        echo "❌ Failed to send email report"
        echo "Response: $response"
        return 1
    fi
}

# Automatic email reporting
echo ""
echo "========================================="
echo "EMAIL REPORTING"
echo "========================================="
echo ""
echo "📧 Generating and sending HTML email report..."

# Generate email subject based on results - Include hostname prominently
# Add performance indicator
perf_emoji=""
if [ "$PERF_GRADE" = "A+" ] || [ "$PERF_GRADE" = "A" ]; then
    perf_emoji="🏆"
elif [ "$PERF_GRADE" = "B" ]; then
    perf_emoji="✅"
elif [ "$PERF_GRADE" = "C" ]; then
    perf_emoji="⚡"
else
    perf_emoji="⚠️"
fi

if [ "$STALE_COUNT" -eq 0 ]; then
    email_subject="$perf_emoji [$(hostname)] Proxmox Health: Grade $PERF_GRADE - HEALTHY ($VALID_COUNT valid entries)"
elif [ "$STALE_COUNT" -lt 10 ]; then
    email_subject="⚠️ [$(hostname)] Proxmox Health: Grade $PERF_GRADE - $STALE_COUNT DM setup entries need cleanup"
else
    email_subject="🚨 [$(hostname)] Proxmox Health: Grade $PERF_GRADE - UN-HEALTHY - $STALE_COUNT DM setup entries"
fi

# Generate and send email
html_report=$(generate_html_email)
if send_mailjet_email "$html_report" "$email_subject"; then
    echo "Email report delivered successfully!"
else
    echo "Email delivery failed. Report still available locally."
fi

# Interactive cleanup option
if [ "$STALE_COUNT" -gt 0 ]; then
    echo ""
    echo "========================================="
    echo "INTERACTIVE CLEANUP OPTION"
    echo "========================================="
    echo ""
    
    # If there are many stale entries, warn the user
    if [ "$STALE_COUNT" -gt 20 ]; then
        echo "WARNING: You have $STALE_COUNT stale entries!"
        echo "This interactive cleanup will prompt you for each one."
        echo ""
    fi
    
    echo "This script will exit in 30 seconds if no selection is made"
    read -t 30 -p "Do you want to interactively clean up stale entries? (y/N): " cleanup_choice
    
    # Check if read timed out (exit code > 0) or if user chose not to cleanup
    if [ $? -ne 0 ]; then
        exit 0
    fi
    
    if [[ $cleanup_choice =~ ^[Yy]$ ]]; then
        echo ""
        echo "Starting interactive cleanup..."
        echo "You will be prompted for each stale entry with an explanation."
        echo "Options: y=remove, n=skip, a=remove all remaining, q=quit"
        echo ""
        
        CLEANED_COUNT=0
        SKIPPED_COUNT=0
        REMOVE_ALL=false
        CURRENT_ENTRY=0
        
        # Process each stale entry from the temp file using file descriptor 3
        exec 3< "$TEMP_FILE"
        while IFS= read -r dm_line <&3; do
            DM_NAME=$(echo "$dm_line" | awk '{print $1}')
            ENTRY_VM_ID=$(echo "$DM_NAME" | sed -n 's/.*vm--\([0-9]\+\)--.*/\1/p')
            
            if [ -n "$ENTRY_VM_ID" ]; then
                # Check if this VM is running (stale entry)
                VM_IS_RUNNING=false
                for running_vm in $RUNNING_VMS; do
                    if [ "$running_vm" = "$ENTRY_VM_ID" ]; then
                        VM_IS_RUNNING=true
                        break
                    fi
                done
                
                if [ "$VM_IS_RUNNING" = "false" ]; then
                    CURRENT_ENTRY=$((CURRENT_ENTRY + 1))
                    
                    # If remove all is set, just remove without prompting
                    if [ "$REMOVE_ALL" = "true" ]; then
                        echo "[$CURRENT_ENTRY/$STALE_COUNT] Auto-removing: $DM_NAME"
                        if dmsetup remove "$DM_NAME" 2>/dev/null; then
                            echo "  ✓ SUCCESS: Removed"
                            CLEANED_COUNT=$((CLEANED_COUNT + 1))
                        else
                            echo "  ✗ FAILED: Could not remove (may already be gone)"
                        fi
                        continue
                    fi
                    
                    # Extract storage info for explanation - fixed regex
                    # Handle various formats like "t1b--ha04-vm--128--disk--2"
                    STORAGE_POOL=$(echo "$DM_NAME" | sed -n 's/^\([^-]*\)\(--[^-]*\)*--vm--.*/\1\2/p' | sed 's/--/-/g')
                    DISK_NUM=$(echo "$DM_NAME" | sed -n 's/.*--disk--\([0-9]\+\).*/\1/p')
                    [ -z "$DISK_NUM" ] && DISK_NUM="Unknown"
                    
                    echo "----------------------------------------"
                    echo "STALE ENTRY $CURRENT_ENTRY of $STALE_COUNT:"
                    echo "  Device: $DM_NAME"
                    echo "  VM ID: $ENTRY_VM_ID"
                    echo "  Storage: $STORAGE_POOL"
                    echo "  Disk: $DISK_NUM"
                    echo ""
                    echo "EXPLANATION:"
                    echo "  VM $ENTRY_VM_ID is not running on this node"
                    echo "  This device mapper entry allows local access to the disk"
                    echo "  Removing it will:"
                    echo "    ✓ Free up local device mapper resources"
                    echo "    ✓ Clean up stale references"
                    echo "    ✓ Prevent 'Device or resource busy' errors"
                    echo "    ✓ NOT affect the actual storage data"
                    echo "    ✓ NOT affect VMs running on other nodes"
                    echo ""
                    echo "SAFETY:"
                    echo "  - Storage data remains untouched"
                    echo "  - Can be recreated if VM migrates back here"
                    echo "  - Only removes local access path"
                    echo ""
                    
                    # Read user input from stdin (not from file descriptor 3)
                    read -p "Remove this stale entry? (y/n/a=all/q=quit): " entry_choice </dev/tty
                    case $entry_choice in
                        [Yy]* ) 
                            echo "  Executing: dmsetup remove $DM_NAME"
                            if dmsetup remove "$DM_NAME" 2>/dev/null; then
                                echo "  ✓ SUCCESS: Removed $DM_NAME"
                                CLEANED_COUNT=$((CLEANED_COUNT + 1))
                            else
                                echo "  ✗ FAILED: Could not remove $DM_NAME (may already be gone)"
                            fi
                            echo ""
                            ;;
                        [Nn]* ) 
                            echo "  SKIPPED: $DM_NAME"
                            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                            echo ""
                            ;;
                        [Aa]* )
                            echo "  REMOVE ALL: Will remove all remaining stale entries without prompting"
                            REMOVE_ALL=true
                            echo "  Executing: dmsetup remove $DM_NAME"
                            if dmsetup remove "$DM_NAME" 2>/dev/null; then
                                echo "  ✓ SUCCESS: Removed $DM_NAME"
                                CLEANED_COUNT=$((CLEANED_COUNT + 1))
                            else
                                echo "  ✗ FAILED: Could not remove $DM_NAME (may already be gone)"
                            fi
                            echo ""
                            ;;
                        [Qq]* ) 
                            echo ""
                            echo "CLEANUP STOPPED BY USER"
                            echo "Cleanup terminated at entry $CURRENT_ENTRY of $STALE_COUNT"
                            break
                            ;;
                        * ) 
                            echo "  Invalid choice, skipping entry."
                            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                            echo ""
                            ;;
                    esac
                fi
            fi
        done
        exec 3<&-  # Close file descriptor 3
        
        echo "========================================="
        echo "CLEANUP COMPLETED"
        echo "========================================="
        echo "Interactive cleanup finished."
        echo "  Total stale entries: $STALE_COUNT"
        echo "  Cleaned: $CLEANED_COUNT entries"
        echo "  Skipped: $SKIPPED_COUNT entries"
        echo "  Remaining: $((STALE_COUNT - CLEANED_COUNT - SKIPPED_COUNT)) entries"
    else
        echo "Cleanup cancelled. No changes made."
    fi
fi

# Clean up temp file
rm -f "$TEMP_FILE"