#!/bin/bash
# VERSION 27 - Proxmox Device Mapper Analysis and Cleanup Script
# FIXED: All bash syntax errors resolved
# Analyzes device mapper entries and provides optional interactive cleanup
# Includes HTML email reporting via Mailjet API

# Mailjet Configuration
MAILJET_API_KEY="c43592765ac7f1368cbe599e4558f9f2"
MAILJET_API_SECRET="9fa6ed98a5a92f0006eefef14f079ac7"
FROM_EMAIL="automation@prosource-demo.com"
FROM_NAME="ProxMox DMSetup Health Check"
TO_EMAIL="klucier@getprosource.com"

echo "Proxmox Device Mapper Analysis and Cleanup Tool v27"
echo "Node: $(hostname)"
echo "Date: $(date)"
echo "Mode: ANALYSIS + CONFIG VALIDATION + OPTIONAL CLEANUP + EMAIL REPORTING"
echo ""

# Initialize all count variables to prevent arithmetic errors
STALE_COUNT=0
VALID_COUNT=0
TOTAL_ENTRIES=0
CONFIG_ORPHANED_COUNT=0
CONFIG_DUPLICATE_COUNT=0
CONFIG_MISSING_COUNT=0
CONFIG_TOTAL_ISSUES=0

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

# Get all VMs (running and stopped) for config validation
echo "All VMs on this node:"
ALL_VMS=$(qm list 2>/dev/null | grep -v VMID | awk '{print $1}')
if [ -z "$ALL_VMS" ]; then
    echo "   No VMs found on this node"
    ALL_VMS=""
else
    echo "   $(echo $ALL_VMS | tr '\n' ' ')"
fi
echo ""

# Get device mapper entries for VMs
echo "Device mapper entries analysis:"
DM_ENTRIES=$(dmsetup ls 2>/dev/null | grep -E 'vm--[0-9]+--disk')

if [ -z "$DM_ENTRIES" ]; then
    echo "   No VM device mapper entries found"
    echo ""
    echo "Status: CLEAN - No device mapper entries to analyze"
else
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
echo "========================================="
echo "CONFIG VALIDATION MODULE"
echo "========================================="
echo ""
echo "Comparing VM configurations against device mapper entries..."

# Create temp files for config validation
CONFIG_TEMP_FILE=$(mktemp)
ORPHANED_TEMP_FILE=$(mktemp)
DUPLICATE_TEMP_FILE=$(mktemp)
MISSING_TEMP_FILE=$(mktemp)

# Function to parse VM disk configuration
parse_vm_config() {
    vm_id="$1"
    config_file="/etc/pve/qemu-server/${vm_id}.conf"
    
    if [ ! -f "$config_file" ]; then
        return 1
    fi
    
    # Extract ALL disk configurations including special disk types
    grep -E "^(virtio|ide|scsi|sata|efidisk|tpmstate|unused)[0-9]+:" "$config_file" | while IFS= read -r line; do
        # Extract storage and disk info
        disk_def=$(echo "$line" | cut -d: -f2- | cut -d, -f1 | xargs)
        
        # Handle different disk patterns
        if echo "$disk_def" | grep -E "^[^:]+:vm-[0-9]+-(disk|tmp-state)-[0-9]+$" >/dev/null; then
            storage_pool=$(echo "$disk_def" | cut -d: -f1)
            disk_name=$(echo "$disk_def" | cut -d: -f2)
            
            # Extract disk number using sed
            disk_num=$(echo "$disk_name" | sed -n 's/.*-\(disk\|tmp-state\)-\([0-9]\+\)$/\2/p')
            
            if [ -n "$disk_num" ]; then
                echo "CONFIG_DISK:${vm_id}:${storage_pool}:${disk_num}"
            fi
        fi
    done
}

# Function to parse device mapper entries into structured format
parse_dm_entries() {
    if [ -f "$TEMP_FILE" ]; then
        while IFS= read -r dm_line; do
            DM_NAME=$(echo "$dm_line" | awk '{print $1}')
            VM_ID=$(echo "$DM_NAME" | sed -n 's/.*vm--\([0-9]\+\)--.*/\1/p')
            
            if [ -n "$VM_ID" ]; then
                # Extract storage pool and disk number
                STORAGE_PART=$(echo "$DM_NAME" | sed -n 's/^\([^-]*\(-[^-]*\)*\)--vm--.*/\1/p' | sed 's/--/-/g')
                DISK_NUM=$(echo "$DM_NAME" | sed -n 's/.*--disk--\([0-9]\+\).*/\1/p')
                
                echo "DM_ENTRY:${VM_ID}:${STORAGE_PART}:${DISK_NUM}:${DM_NAME}"
            fi
        done < "$TEMP_FILE"
    fi
}

echo "Parsing VM configurations..."
for vm_id in $ALL_VMS; do
    echo "  Parsing VM $vm_id config..."
    parse_vm_config "$vm_id" >> "$CONFIG_TEMP_FILE"
done

echo "Found $(wc -l < "$CONFIG_TEMP_FILE" 2>/dev/null || echo 0) disk configurations in VM configs"
if [ -s "$CONFIG_TEMP_FILE" ]; then
    echo "Sample config entries:"
    head -5 "$CONFIG_TEMP_FILE" | sed 's/^/    /'
fi

echo "Analyzing configuration vs device mapper mismatches..."

# Parse DM entries into structured format
DM_STRUCTURED_FILE=$(mktemp)
parse_dm_entries > "$DM_STRUCTURED_FILE"

echo "Found $(wc -l < "$DM_STRUCTURED_FILE" 2>/dev/null || echo 0) device mapper entries"
if [ -s "$DM_STRUCTURED_FILE" ]; then
    echo "Sample DM entries:"
    head -5 "$DM_STRUCTURED_FILE" | sed 's/^/    /'
fi

# Check for orphaned DM entries (DM entries with no corresponding config)
echo ""
echo "Checking for orphaned device mapper entries..."
while IFS= read -r dm_line; do
    if [[ "$dm_line" =~ ^DM_ENTRY: ]]; then
        VM_ID=$(echo "$dm_line" | cut -d: -f2)
        STORAGE=$(echo "$dm_line" | cut -d: -f3)
        DISK_NUM=$(echo "$dm_line" | cut -d: -f4)
        DM_NAME=$(echo "$dm_line" | cut -d: -f5)
        
        # Check if this VM exists in our VM list
        VM_EXISTS=false
        for vm in $ALL_VMS; do
            if [ "$vm" = "$VM_ID" ]; then
                VM_EXISTS=true
                break
            fi
        done
        
        if [ "$VM_EXISTS" = "false" ]; then
            echo "ORPHANED: $DM_NAME (VM $VM_ID does not exist on this node)"
            echo "$dm_line" >> "$ORPHANED_TEMP_FILE"
            CONFIG_ORPHANED_COUNT=$((CONFIG_ORPHANED_COUNT + 1))
        else
            # VM exists, check if this disk is in the config
            DISK_IN_CONFIG=false
            while IFS= read -r config_line; do
                if [[ "$config_line" =~ ^CONFIG_DISK:${VM_ID}: ]] && [[ "$config_line" =~ :${DISK_NUM}$ ]]; then
                    DISK_IN_CONFIG=true
                    break
                fi
            done < "$CONFIG_TEMP_FILE"
            
            if [ "$DISK_IN_CONFIG" = "false" ]; then
                echo "ORPHANED: $DM_NAME (VM $VM_ID exists but disk $DISK_NUM not in config)"
                echo "$dm_line" >> "$ORPHANED_TEMP_FILE"
                CONFIG_ORPHANED_COUNT=$((CONFIG_ORPHANED_COUNT + 1))
            fi
        fi
    fi
done < "$DM_STRUCTURED_FILE"

# Check for duplicate DM entries
echo ""
echo "Checking for duplicate device mapper entries..."
sort "$DM_STRUCTURED_FILE" | uniq -c | while read count line; do
    if [ "$count" -gt 1 ] && [[ "$line" =~ ^DM_ENTRY: ]]; then
        VM_ID=$(echo "$line" | cut -d: -f2)
        DISK_NUM=$(echo "$line" | cut -d: -f4)
        echo "DUPLICATE: VM $VM_ID disk $DISK_NUM has $count device mapper entries"
        echo "$line:COUNT:$count" >> "$DUPLICATE_TEMP_FILE"
        CONFIG_DUPLICATE_COUNT=$((CONFIG_DUPLICATE_COUNT + 1))
    fi
done

# Check for missing DM entries (config expects disk but no DM entry)
echo ""
echo "Checking for missing device mapper entries..."
while IFS= read -r config_line; do
    if [[ "$config_line" =~ ^CONFIG_DISK: ]]; then
        VM_ID=$(echo "$config_line" | cut -d: -f2)
        STORAGE=$(echo "$config_line" | cut -d: -f3)
        DISK_NUM=$(echo "$config_line" | cut -d: -f4)
        
        # Check if there's a corresponding DM entry
        DM_EXISTS=false
        while IFS= read -r dm_line; do
            if [[ "$dm_line" =~ ^DM_ENTRY:${VM_ID}: ]] && [[ "$dm_line" =~ :${DISK_NUM}: ]]; then
                DM_EXISTS=true
                break
            fi
        done < "$DM_STRUCTURED_FILE"
        
        if [ "$DM_EXISTS" = "false" ]; then
            echo "MISSING: VM $VM_ID disk $DISK_NUM (${STORAGE}:vm-${VM_ID}-disk-${DISK_NUM}) has no device mapper entry"
            echo "$config_line" >> "$MISSING_TEMP_FILE"
            CONFIG_MISSING_COUNT=$((CONFIG_MISSING_COUNT + 1))
        fi
    fi
done < "$CONFIG_TEMP_FILE"

# Calculate total config issues
CONFIG_TOTAL_ISSUES=$((CONFIG_ORPHANED_COUNT + CONFIG_DUPLICATE_COUNT + CONFIG_MISSING_COUNT))

echo ""
echo "Config Validation Summary:"
echo "   Orphaned DM entries: $CONFIG_ORPHANED_COUNT"
echo "   Duplicate DM entries: $CONFIG_DUPLICATE_COUNT"
echo "   Missing DM entries: $CONFIG_MISSING_COUNT"
echo "   Total config issues: $CONFIG_TOTAL_ISSUES"

if [ "$CONFIG_TOTAL_ISSUES" -eq 0 ]; then
    echo ""
    echo "Status: CONFIG HEALTHY - All device mapper entries match VM configurations"
else
    echo ""
    echo "Status: CONFIG ISSUES DETECTED - Review recommended"
    echo "Recommendation: Use interactive cleanup to resolve configuration mismatches"
fi

echo ""
echo "Analysis completed - no changes made during analysis phase"

# Gather system metrics for email report
echo ""
echo "Gathering system metrics for report..."
HOST_UPTIME=$(uptime -p | sed 's/up //')
HOST_LOAD=$(uptime | awk -F'load average:' '{print $2}' | xargs)
HOST_CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
HOST_CPU_CORES=$(nproc)
HOST_TOTAL_RAM=$(free -h | awk '/^Mem:/ {print $2}')
HOST_USED_RAM=$(free -h | awk '/^Mem:/ {print $3}')
HOST_RAM_PERCENT=$(free | awk '/^Mem:/ {printf "%.0f", $3/$2 * 100}')
HOST_PROXMOX_VERSION=$(pveversion -v | grep "pve-manager" | awk '{print $2}')
HOST_KERNEL=$(uname -r)

# Get CPU usage - simple approach
HOST_CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d. -f1)
if [ -z "$HOST_CPU_USAGE" ] || ! [[ "$HOST_CPU_USAGE" =~ ^[0-9]+$ ]]; then
    HOST_CPU_USAGE="0"
fi

HOST_TOTAL_VMS=$(qm list 2>/dev/null | grep -v VMID | wc -l)
HOST_STOPPED_VMS=$(qm list 2>/dev/null | grep stopped | wc -l)
HOST_SYSTEM_MODEL=$(dmidecode -s system-product-name 2>/dev/null || echo "Unknown")

# Get storage usage for main partitions
HOST_ROOT_USAGE=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')

# Get network interface with most traffic
HOST_PRIMARY_NET=$(ip route | grep default | awk '{print $5}' | head -1)
HOST_NET_IP=$(ip -4 addr show $HOST_PRIMARY_NET 2>/dev/null | grep inet | awk '{print $2}' | head -1 || echo "N/A")

# Get container (LXC) count
HOST_TOTAL_CTS=$(pct list 2>/dev/null | grep -v VMID | wc -l)
HOST_RUNNING_CTS=$(pct list 2>/dev/null | grep running | wc -l)

# Calculate performance grade
PERF_SCORE=100

# Ensure we have valid numeric values
HOST_CPU_USAGE=${HOST_CPU_USAGE:-0}
HOST_RAM_PERCENT=${HOST_RAM_PERCENT:-0}
STALE_COUNT=${STALE_COUNT:-0}
CONFIG_TOTAL_ISSUES=${CONFIG_TOTAL_ISSUES:-0}

# Deduct points for high resource usage
if [[ "$HOST_CPU_USAGE" =~ ^[0-9]+$ ]]; then
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

# Deduct for config issues
[ $CONFIG_TOTAL_ISSUES -gt 20 ] && PERF_SCORE=$((PERF_SCORE - 15))
[ $CONFIG_TOTAL_ISSUES -gt 5 ] && [ $CONFIG_TOTAL_ISSUES -le 20 ] && PERF_SCORE=$((PERF_SCORE - 8))

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

# Function to generate HTML email report
generate_html_email() {
    status_color=""
    status_text=""
    status_bg_color=""
    
    # Determine overall status
    total_issues=$((STALE_COUNT + CONFIG_TOTAL_ISSUES))
    if [ "$total_issues" -eq 0 ]; then
        status_color="#155724"
        status_bg_color="#d4edda"
        status_text="HEALTHY"
    elif [ "$total_issues" -lt 10 ]; then
        status_color="#856404"
        status_bg_color="#fff3cd"
        status_text="WARNING"
    else
        status_color="#721c24"
        status_bg_color="#f8d7da"
        status_text="UN-HEALTHY"
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
        .alert { background-color: #fff3cd; color: #856404; padding: 15px; border-radius: 6px; border-left: 4px solid #ffc107; margin: 15px 0; }
        .success { background-color: #d4edda; color: #155724; padding: 15px; border-radius: 6px; border-left: 4px solid #28a745; margin: 15px 0; }
        .metric-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 15px; margin: 15px 0; }
        .metric-item { background-color: #f8f9fa; padding: 15px; border-radius: 6px; border: 1px solid #dee2e6; }
        .metric-label { font-weight: bold; color: #495057; margin-bottom: 5px; }
        .metric-value { color: #212529; font-size: 1.1em; }
        .section { margin: 20px 0; padding: 15px; background-color: #f9f9f9; border-radius: 6px; border: 1px solid #dee2e6; }
        .footer { margin-top: 20px; padding-top: 20px; border-top: 1px solid #dee2e6; color: #6c757d; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class='container'>
        <div style='font-size: 0.9em; color: #6c757d; margin-bottom: 20px; border-bottom: 1px solid #dee2e6; padding-bottom: 10px;'>
EOF
    echo "            <p>Proxmox Device Mapper Health Check Report v27 - $(date '+%Y-%m-%d %H:%M:%S')</p>"
    echo "        </div>"
    echo "        "
    echo "        <div class='title-header'>"
    echo "            <h1>$(hostname) - Proxmox Health Report</h1>"
    echo "            <p style='margin: 10px 0 0 0; font-size: 14px; opacity: 0.9;'>Performance Grade: <strong>$PERF_GRADE</strong></p>"
    echo "        </div>"
    echo "        "
    
    total_issues=$((STALE_COUNT + CONFIG_TOTAL_ISSUES))
    if [ "$total_issues" -gt 0 ]; then
        echo "        <div class='alert' style='background-color: $status_bg_color; color: $status_color; border-left-color: $([ "$total_issues" -lt 10 ] && echo "#ffc107" || echo "#dc3545");'>"
        echo "            <strong>⚠️ ATTENTION:</strong> $STALE_COUNT DM stale entries + $CONFIG_TOTAL_ISSUES config issues detected"
        echo "            <p style='font-size: 0.9em; color: #666; margin: 10px 0;'>Issues found in device mapper setup. Run interactive cleanup: <span style='background-color: #e9ecef; color: #212529; padding: 2px 4px; border-radius: 3px; font-family: Courier New, monospace; font-size: 0.9em;'>./ProsourceProx-stale-dm.sh</span></p>"
        echo "        </div>"
    else
        echo "        <div class='success'>"
        echo "            <strong>✅ HEALTHY:</strong> All device mapper entries are valid and match VM configurations"
        echo "        </div>"
    fi
    
    echo "        <div class='section-header'><h3>📊 Device Mapper Statistics</h3></div>"
    echo "        <div class='section'><div class='metric-grid'>"
    echo "            <div class='metric-item'><div class='metric-label'>Total Entries</div><div class='metric-value'>$TOTAL_ENTRIES</div></div>"
    echo "            <div class='metric-item'><div class='metric-label'>Valid Entries</div><div class='metric-value' style='color: #28a745;'>$VALID_COUNT</div></div>"
    echo "            <div class='metric-item'><div class='metric-label'>Stale Entries</div><div class='metric-value' style='color: $([ "$STALE_COUNT" -eq 0 ] && echo "#28a745" || echo "#dc3545");'>$STALE_COUNT</div></div>"
    echo "            <div class='metric-item'><div class='metric-label'>Running VMs</div><div class='metric-value' style='color: #17a2b8;'>$(echo $RUNNING_VMS | wc -w)</div></div>"
    echo "        </div></div>"
    
    echo "        <div class='section-header'><h3>🔧 Config Validation Results</h3></div>"
    echo "        <div class='section'><div class='metric-grid'>"
    echo "            <div class='metric-item'><div class='metric-label'>Orphaned Entries</div><div class='metric-value' style='color: $([ "$CONFIG_ORPHANED_COUNT" -eq 0 ] && echo "#28a745" || echo "#dc3545");'>$CONFIG_ORPHANED_COUNT</div></div>"
    echo "            <div class='metric-item'><div class='metric-label'>Duplicate Entries</div><div class='metric-value' style='color: $([ "$CONFIG_DUPLICATE_COUNT" -eq 0 ] && echo "#28a745" || echo "#dc3545");'>$CONFIG_DUPLICATE_COUNT</div></div>"
    echo "            <div class='metric-item'><div class='metric-label'>Missing Entries</div><div class='metric-value' style='color: $([ "$CONFIG_MISSING_COUNT" -eq 0 ] && echo "#28a745" || echo "#ffc107");'>$CONFIG_MISSING_COUNT</div></div>"
    echo "            <div class='metric-item'><div class='metric-label'>Total Config Issues</div><div class='metric-value' style='color: $([ "$CONFIG_TOTAL_ISSUES" -eq 0 ] && echo "#28a745" || echo "#dc3545");'>$CONFIG_TOTAL_ISSUES</div></div>"
    echo "        </div></div>"
    
    echo "        <div class='section-header'><h3>🖥️ Host Information</h3></div>"
    echo "        <div class='section'><div class='metric-grid'>"
    echo "            <div class='metric-item'><div class='metric-label'>Proxmox Version</div><div class='metric-value'>$HOST_PROXMOX_VERSION</div></div>"
    echo "            <div class='metric-item'><div class='metric-label'>Uptime</div><div class='metric-value'>$HOST_UPTIME</div></div>"
    echo "            <div class='metric-item'><div class='metric-label'>CPU Usage</div><div class='metric-value'>${HOST_CPU_USAGE}%</div></div>"
    echo "            <div class='metric-item'><div class='metric-label'>RAM Usage</div><div class='metric-value'>$HOST_USED_RAM / $HOST_TOTAL_RAM (${HOST_RAM_PERCENT}%)</div></div>"
    echo "            <div class='metric-item'><div class='metric-label'>Virtual Machines</div><div class='metric-value'>$HOST_TOTAL_VMS total ($(echo $RUNNING_VMS | wc -w) running)</div></div>"
    echo "            <div class='metric-item'><div class='metric-label'>Storage Usage</div><div class='metric-value'>$HOST_ROOT_USAGE</div></div>"
    echo "        </div></div>"
    
    total_issues=$((STALE_COUNT + CONFIG_TOTAL_ISSUES))
    if [ "$total_issues" -gt 0 ]; then
        echo "        <div class='section'><div class='alert'>"
        echo "            <h3 style='margin: 0 0 15px 0; color: $status_color;'>⚠️ Action Required</h3>"
        echo "            <p><strong>$STALE_COUNT stale entries + $CONFIG_TOTAL_ISSUES config issues detected.</strong></p>"
        echo "            <p>These issues can prevent VMs from starting and cause \"Device or resource busy\" errors.</p>"
        echo "            <p><strong>Recommended Action:</strong> Run the interactive cleanup script during next maintenance window.</p>"
        echo "        </div></div>"
    else
        echo "        <div class='section'><div class='success'>"
        echo "            <h3 style='margin: 0 0 15px 0; color: #155724;'>✅ System Status: Healthy</h3>"
        echo "            <p>No stale entries or configuration issues found. All device mapper entries match VM configurations perfectly.</p>"
        echo "        </div></div>"
    fi
    
    echo "        <div class='footer'>"
    echo "            <p><strong>ProxMox DMSetup Health Check v27</strong></p>"
    echo "            <p>Node: <strong>$(hostname)</strong> • Generated: $(date)</p>"
    echo "        </div>"
    echo "    </div>"
    echo "</body>"
    echo "</html>"
}

# Function to send email via Mailjet
send_mailjet_email() {
    html_content="$1"
    subject="$2"
    
    # Escape HTML for JSON
    html_escaped=$(echo "$html_content" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr '\n' ' ')
    
    # Create JSON payload
    json_payload="{\"Messages\":[{\"From\":{\"Email\":\"$FROM_EMAIL\",\"Name\":\"$FROM_NAME\"},\"To\":[{\"Email\":\"$TO_EMAIL\"}],\"Subject\":\"$subject\",\"HTMLPart\":\"$html_escaped\",\"TextPart\":\"Proxmox Device Mapper Report for $(hostname) - $STALE_COUNT stale entries + $CONFIG_TOTAL_ISSUES config issues found.\"}]}"
    
    # Send email via Mailjet API
    response=$(curl -s -X POST \
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

# Generate email subject
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

total_issues=$((STALE_COUNT + CONFIG_TOTAL_ISSUES))
if [ "$total_issues" -eq 0 ]; then
    email_subject="$perf_emoji [$(hostname)] Proxmox Health: Grade $PERF_GRADE - HEALTHY (All systems optimal)"
elif [ "$total_issues" -lt 10 ]; then
    email_subject="⚠️ [$(hostname)] Proxmox Health: Grade $PERF_GRADE - $total_issues issues need attention"
else
    email_subject="🚨 [$(hostname)] Proxmox Health: Grade $PERF_GRADE - UN-HEALTHY - $total_issues critical issues"
fi

# Generate and send email
html_report=$(generate_html_email)
if send_mailjet_email "$html_report" "$email_subject"; then
    echo "Email report delivered successfully!"
else
    echo "Email delivery failed. Report still available locally."
fi

# Interactive cleanup option
if [ "$STALE_COUNT" -gt 0 ] || [ "$CONFIG_TOTAL_ISSUES" -gt 0 ]; then
    echo ""
    echo "========================================="
    echo "INTERACTIVE CLEANUP OPTION"
    echo "========================================="
    echo ""
    
    # Show summary of issues
    echo "Issues detected:"
    echo "  • Stale DM entries: $STALE_COUNT"
    echo "  • Orphaned entries: $CONFIG_ORPHANED_COUNT"
    echo "  • Duplicate entries: $CONFIG_DUPLICATE_COUNT"
    echo "  • Missing entries: $CONFIG_MISSING_COUNT"
    echo ""
    
    # If there are many issues, warn the user
    total_cleanable=$((STALE_COUNT + CONFIG_ORPHANED_COUNT + CONFIG_DUPLICATE_COUNT))
    if [ "$total_cleanable" -gt 20 ]; then
        echo "WARNING: You have $total_cleanable entries that can be cleaned up!"
        echo "This interactive cleanup will prompt you for each one."
        echo ""
    fi
    
    echo "This script will exit in 30 seconds if no selection is made"
    read -t 30 -p "Do you want to interactively clean up issues? (y/N): " cleanup_choice
    
    # Check if read timed out or user chose not to cleanup
    if [ $? -ne 0 ]; then
        exit 0
    fi
    
    if [[ $cleanup_choice =~ ^[Yy]$ ]]; then
        echo ""
        echo "Starting interactive cleanup..."
        echo "You will be prompted for each issue with an explanation."
        echo "Options: y=remove, n=skip, a=remove all remaining, q=quit"
        echo ""
        
        CLEANED_COUNT=0
        SKIPPED_COUNT=0
        REMOVE_ALL=false
        CURRENT_ENTRY=0
        
        # Handle stale entries
        if [ "$STALE_COUNT" -gt 0 ]; then
            echo "========== CLEANING STALE DM ENTRIES =========="
            exec 3< "$TEMP_FILE"
            while IFS= read -r dm_line <&3; do
                DM_NAME=$(echo "$dm_line" | awk '{print $1}')
                ENTRY_VM_ID=$(echo "$DM_NAME" | sed -n 's/.*vm--\([0-9]\+\)--.*/\1/p')
                
                if [ -n "$ENTRY_VM_ID" ]; then
                    # Check if this VM is running
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
                        
                        echo "----------------------------------------"
                        echo "STALE ENTRY $CURRENT_ENTRY of $STALE_COUNT:"
                        echo "  Device: $DM_NAME"
                        echo "  VM ID: $ENTRY_VM_ID"
                        echo ""
                        echo "EXPLANATION:"
                        echo "  VM $ENTRY_VM_ID is not running on this node"
                        echo "  Removing it will:"
                        echo "    ✓ Free up local device mapper resources"
                        echo "    ✓ Clean up stale references"
                        echo "    ✓ Prevent 'Device or resource busy' errors"
                        echo "    ✓ NOT affect the actual storage data"
                        echo ""
                        
                        # Read user input
                        read -p "Remove this stale entry? (y/n/a=all/q=quit): " entry_choice </dev/tty
                        case $entry_choice in
                            [Yy]* ) 
                                echo "  Executing: dmsetup remove $DM_NAME"
                                if dmsetup remove "$DM_NAME" 2>/dev/null; then
                                    echo "  ✓ SUCCESS: Removed $DM_NAME"
                                    CLEANED_COUNT=$((CLEANED_COUNT + 1))
                                else
                                    echo "  ✗ FAILED: Could not remove $DM_NAME"
                                fi
                                ;;
                            [Nn]* ) 
                                echo "  SKIPPED: $DM_NAME"
                                SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                                ;;
                            [Aa]* )
                                echo "  REMOVE ALL: Will remove all remaining stale entries"
                                REMOVE_ALL=true
                                if dmsetup remove "$DM_NAME" 2>/dev/null; then
                                    echo "  ✓ SUCCESS: Removed $DM_NAME"
                                    CLEANED_COUNT=$((CLEANED_COUNT + 1))
                                else
                                    echo "  ✗ FAILED: Could not remove $DM_NAME"
                                fi
                                ;;
                            [Qq]* ) 
                                echo ""
                                echo "CLEANUP STOPPED BY USER"
                                break
                                ;;
                            * ) 
                                echo "  Invalid choice, skipping entry."
                                SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                                ;;
                        esac
                    fi
                fi
            done
            exec 3<&-
        fi
        
        # Handle orphaned config entries
        if [ "$CONFIG_ORPHANED_COUNT" -gt 0 ] && [[ ! $cleanup_choice =~ ^[Qq]$ ]]; then
            echo ""
            echo "========== CLEANING ORPHANED CONFIG ENTRIES =========="
            CURRENT_ENTRY=0
            while IFS= read -r orphan_line; do
                if [[ "$orphan_line" =~ ^DM_ENTRY: ]]; then
                    CURRENT_ENTRY=$((CURRENT_ENTRY + 1))
                    VM_ID=$(echo "$orphan_line" | cut -d: -f2)
                    DM_NAME=$(echo "$orphan_line" | cut -d: -f5)
                    
                    echo "----------------------------------------"
                    echo "ORPHANED CONFIG ENTRY $CURRENT_ENTRY of $CONFIG_ORPHANED_COUNT:"
                    echo "  Device: $DM_NAME"
                    echo "  VM ID: $VM_ID"
                    echo ""
                    echo "EXPLANATION:"
                    echo "  This device mapper entry doesn't match any VM configuration"
                    echo "  Removing it will:"
                    echo "    ✓ Clean up configuration mismatches"
                    echo "    ✓ Prevent VM startup issues"
                    echo "    ✓ NOT affect actual storage data"
                    echo ""
                    
                    read -p "Remove this orphaned entry? (y/n/q=quit): " entry_choice </dev/tty
                    case $entry_choice in
                        [Yy]* ) 
                            echo "  Executing: dmsetup remove $DM_NAME"
                            if dmsetup remove "$DM_NAME" 2>/dev/null; then
                                echo "  ✓ SUCCESS: Removed $DM_NAME"
                                CLEANED_COUNT=$((CLEANED_COUNT + 1))
                            else
                                echo "  ✗ FAILED: Could not remove $DM_NAME"
                            fi
                            ;;
                        [Nn]* ) 
                            echo "  SKIPPED: $DM_NAME"
                            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                            ;;
                        [Qq]* ) 
                            echo ""
                            echo "CLEANUP STOPPED BY USER"
                            break
                            ;;
                        * ) 
                            echo "  Invalid choice, skipping entry."
                            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                            ;;
                    esac
                fi
            done < "$ORPHANED_TEMP_FILE"
        fi
        
        echo "========================================="
        echo "CLEANUP COMPLETED"
        echo "========================================="
        echo "Interactive cleanup finished."
        echo "  Total issues addressed: $((STALE_COUNT + CONFIG_ORPHANED_COUNT))"
        echo "  Cleaned: $CLEANED_COUNT entries"
        echo "  Skipped: $SKIPPED_COUNT entries"
    else
        echo "Cleanup cancelled. No changes made."
    fi
fi

# Clean up temp files
rm -f "$TEMP_FILE" "$CONFIG_TEMP_FILE" "$ORPHANED_TEMP_FILE" "$DUPLICATE_TEMP_FILE" "$MISSING_TEMP_FILE" "$DM_STRUCTURED_FILE" 2>/dev/null || true