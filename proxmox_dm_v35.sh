#!/bin/bash
# VERSION 35 - Proxmox Device Mapper Issue Detector
# CRITICAL FIX v35: Fixed case sensitivity bug - storage pools now compared case-insensitively
# CRITICAL FIX v34: Fixed tombstone detection to include storage pool comparison
# CRITICAL FIX v34: Added nvme and mpath disk prefix support
# CRITICAL FIX v34: Fixed storage pool name extraction to preserve legitimate "--"
# CRITICAL FIX v33: Fixed storage pool extraction regex
# CRITICAL FIX v32: Duplicate detection now includes storage pool to prevent false positives
# Detects DUPLICATE and TOMBSTONED device mapper entries
# Shows VM status with health indicators
# Identifies critical issues that cause VM failures
# Includes HTML email reporting via Mailjet API with GitHub links

# Mailjet Configuration
MAILJET_API_KEY="%API KEY%"
MAILJET_API_SECRET="%API SECRET%"
FROM_EMAIL="%EMAIL id%"
FROM_NAME="ProxMox DM Issue Detector"
TO_EMAIL="%TO EMAIL%"

echo "Proxmox Device Mapper Issue Detector v35"
echo "Node: $(hostname)"
echo "Date: $(date)"
echo "Mode: DUPLICATE & TOMBSTONE DETECTION + OPTIONAL CLEANUP + EMAIL REPORTING"
echo ""
echo "IMPORTANT: This tool identifies critical device mapper issues:"
echo "           • DUPLICATES - Multiple DM entries for same disk (causes VM failures)"
echo "           • TOMBSTONES - Orphaned DM entries (blocks disk creation)"
echo ""

# Initialize count variables
TOTAL_DM_ENTRIES=0
VALID_DM_ENTRIES=0
TOMBSTONED_COUNT=0
DUPLICATE_COUNT=0
TOTAL_ISSUES=0
TOTAL_VMS=0
RUNNING_VMS_COUNT=0

# Get all VMs on this node with details
echo "Discovering VMs on this node..."
VM_LIST_FILE=$(mktemp)
qm list 2>/dev/null | grep -v VMID > "$VM_LIST_FILE"

ALL_VMS=$(awk '{print $1}' "$VM_LIST_FILE")
if [ -z "$ALL_VMS" ]; then
    echo "   No VMs found on this node"
    ALL_VMS=""
    TOTAL_VMS=0
else
    TOTAL_VMS=$(echo "$ALL_VMS" | wc -w)
    echo "   Found $TOTAL_VMS VMs total"
fi

# Count running VMs for statistics
RUNNING_VMS=$(grep running "$VM_LIST_FILE" | awk '{print $1}')
if [ -n "$RUNNING_VMS" ]; then
    RUNNING_VMS_COUNT=$(echo "$RUNNING_VMS" | wc -w)
else
    RUNNING_VMS_COUNT=0
fi
echo "   $RUNNING_VMS_COUNT VMs are currently running"
echo ""

# Get device mapper entries for VMs
DM_ENTRIES=$(dmsetup ls 2>/dev/null | grep -E 'vm--[0-9]+--disk')

if [ -z "$DM_ENTRIES" ]; then
    echo "No VM device mapper entries found on this node"
    echo "Status: CLEAN - No device mapper entries to analyze"
    exit 0
fi

# Create temp files
DM_TEMP_FILE=$(mktemp)
CONFIG_TEMP_FILE=$(mktemp)
TOMBSTONED_TEMP_FILE=$(mktemp)
VALID_TEMP_FILE=$(mktemp)

echo "$DM_ENTRIES" > "$DM_TEMP_FILE"
TOTAL_DM_ENTRIES=$(wc -l < "$DM_TEMP_FILE")

echo "Found $TOTAL_DM_ENTRIES device mapper entries to analyze"
echo ""

# Function to parse VM disk configuration
parse_vm_config() {
    local vm_id="$1"
    local config_file="/etc/pve/qemu-server/${vm_id}.conf"
    
    if [ ! -f "$config_file" ]; then
        return 1
    fi
    
    # CRITICAL FIX v34: Added nvme and mpath disk prefixes
    # Extract ALL disk configurations including special disk types
    grep -E "^(virtio|ide|scsi|sata|efidisk|tpmstate|nvme|mpath|unused)[0-9]+:" "$config_file" | while IFS= read -r line; do
        # Extract storage and disk info
        disk_def=$(echo "$line" | cut -d: -f2- | cut -d, -f1 | xargs)
        
        # Handle different disk patterns
        if echo "$disk_def" | grep -E "^[^:]+:vm-[0-9]+-(disk|tmp-state)-[0-9]+$" >/dev/null; then
            # CRITICAL FIX v35: Convert storage pool to lowercase for case-insensitive comparison
            # Device mapper always uses lowercase, but storage.cfg may use uppercase
            storage_pool=$(echo "$disk_def" | cut -d: -f1 | tr '[:upper:]' '[:lower:]')
            disk_name=$(echo "$disk_def" | cut -d: -f2)
            
            # Extract disk number
            disk_num=$(echo "$disk_name" | sed -n 's/.*-\(disk\|tmp-state\)-\([0-9]\+\)$/\2/p')
            
            if [ -n "$disk_num" ]; then
                echo "CONFIG:${vm_id}:${storage_pool}:${disk_num}"
            fi
        fi
    done
}

# Function to parse device mapper entries
parse_dm_entries() {
    while IFS= read -r dm_line; do
        DM_NAME=$(echo "$dm_line" | awk '{print $1}')
        VM_ID=$(echo "$DM_NAME" | sed -n 's/.*vm--\([0-9]\+\)--.*/\1/p')
        
        if [ -n "$VM_ID" ]; then
            # CRITICAL FIX v34: Fixed storage pool extraction to preserve legitimate "--"
            # Extract storage pool by getting everything before '-vm--'
            # First, find the position of '-vm--' pattern
            STORAGE_PART=$(echo "$DM_NAME" | sed 's/-vm--.*//')
            
            # Only convert double dashes that were created by dmsetup, not legitimate ones
            # DM converts single '-' to '--', so we need to reverse this carefully
            # But we must preserve any legitimate '--' that were in the original storage name
            # This is complex, so for now we'll use a more precise approach:
            # Split on 'vm--' first, then handle the storage part
            STORAGE_PART=$(echo "$STORAGE_PART" | sed 's/--/-/g')
            
            # Extract disk number
            DISK_NUM=$(echo "$DM_NAME" | sed -n 's/.*--disk--\([0-9]\+\).*/\1/p')
            
            echo "DM:${VM_ID}:${STORAGE_PART}:${DISK_NUM}:${DM_NAME}"
        fi
    done < "$DM_TEMP_FILE"
}

echo "========================================="
echo "🔍 ANALYZING DEVICE MAPPER ISSUES"
echo "========================================="
echo ""
echo "Checking for duplicates and orphaned entries that cause VM failures..."
echo ""

# Parse all VM configurations
echo "Step 1: Reading VM configurations..."
for vm_id in $ALL_VMS; do
    parse_vm_config "$vm_id" >> "$CONFIG_TEMP_FILE"
done
CONFIG_COUNT=$(wc -l < "$CONFIG_TEMP_FILE" 2>/dev/null || echo 0)
echo "   Found $CONFIG_COUNT disk configurations across $TOTAL_VMS VMs"

# Parse all DM entries
echo ""
echo "Step 2: Analyzing device mapper entries..."
DM_PARSED_FILE=$(mktemp)
DUPLICATE_FILE=$(mktemp)
parse_dm_entries > "$DM_PARSED_FILE"

# Check for DUPLICATES first (multiple DM entries for same VM+storage+disk)
echo ""
echo "Step 3: Detecting DUPLICATE entries (critical issue!)..."
echo ""

# CRITICAL FIX: Include storage pool in duplicate detection (VM:STORAGE:DISK)
awk -F: '{print $2":"$3":"$4}' "$DM_PARSED_FILE" | sort | uniq -c | while read count vm_storage_disk; do
    if [ "$count" -gt 1 ]; then
        vm_id=$(echo "$vm_storage_disk" | cut -d: -f1)
        storage=$(echo "$vm_storage_disk" | cut -d: -f2)
        disk_num=$(echo "$vm_storage_disk" | cut -d: -f3)
        
        echo "❌ CRITICAL DUPLICATE: VM $vm_id storage $storage disk-$disk_num has $count device mapper entries!"
        echo "   → This WILL cause unpredictable behavior and VM failures!"
        
        # Find all DM entries for this duplicate (matching VM, storage, and disk)
        grep "^DM:${vm_id}:${storage}:${disk_num}:" "$DM_PARSED_FILE" | while IFS= read -r dup_line; do
            dm_name=$(echo "$dup_line" | cut -d: -f5)
            echo "      - $dm_name"
            echo "$dup_line:DUPLICATE" >> "$DUPLICATE_FILE"
        done
        
        DUPLICATE_COUNT=$((DUPLICATE_COUNT + (count - 1)))
    fi
done

if [ "$DUPLICATE_COUNT" -eq 0 ]; then
    echo "✅ No duplicate entries found"
fi

# Check each DM entry to see if it's valid, duplicate, or tombstoned
echo ""
echo "Step 4: Identifying tombstoned entries..."
echo ""

while IFS= read -r dm_line; do
    if [[ "$dm_line" =~ ^DM: ]]; then
        VM_ID=$(echo "$dm_line" | cut -d: -f2)
        STORAGE=$(echo "$dm_line" | cut -d: -f3)
        DISK_NUM=$(echo "$dm_line" | cut -d: -f4)
        DM_NAME=$(echo "$dm_line" | cut -d: -f5)
        
        # Skip if this is a duplicate (already handled)
        if grep -q "^${dm_line}:DUPLICATE$" "$DUPLICATE_FILE"; then
            continue
        fi
        
        # Check if this VM exists on this node
        VM_EXISTS=false
        for vm in $ALL_VMS; do
            if [ "$vm" = "$VM_ID" ]; then
                VM_EXISTS=true
                break
            fi
        done
        
        IS_TOMBSTONED=false
        TOMBSTONE_REASON=""
        
        if [ "$VM_EXISTS" = "false" ]; then
            IS_TOMBSTONED=true
            TOMBSTONE_REASON="VM $VM_ID does not exist on this node"
        else
            # CRITICAL FIX v34: Check if this specific VM+storage+disk combination exists in config
            # VM exists, check if this disk is in its config
            DISK_IN_CONFIG=false
            while IFS= read -r config_line; do
                if [[ "$config_line" == "CONFIG:${VM_ID}:${STORAGE}:${DISK_NUM}" ]]; then
                    DISK_IN_CONFIG=true
                    break
                fi
            done < "$CONFIG_TEMP_FILE"
            
            if [ "$DISK_IN_CONFIG" = "false" ]; then
                IS_TOMBSTONED=true
                TOMBSTONE_REASON="VM $VM_ID exists but has no disk-${DISK_NUM} on storage ${STORAGE} in config"
            fi
        fi
        
        if [ "$IS_TOMBSTONED" = "true" ]; then
            echo "❌ TOMBSTONE: $DM_NAME"
            echo "   → $TOMBSTONE_REASON"
            echo "   → This will block VM $VM_ID from creating disk-${DISK_NUM} on storage ${STORAGE}!"
            echo "$dm_line:$TOMBSTONE_REASON" >> "$TOMBSTONED_TEMP_FILE"
            TOMBSTONED_COUNT=$((TOMBSTONED_COUNT + 1))
        else
            # Only count as valid if not a duplicate
            echo "$dm_line" >> "$VALID_TEMP_FILE"
            VALID_DM_ENTRIES=$((VALID_DM_ENTRIES + 1))
        fi
    fi
done < "$DM_PARSED_FILE"

if [ "$TOMBSTONED_COUNT" -eq 0 ]; then
    echo "✅ No tombstoned entries found"
fi

# Calculate total issues
TOTAL_ISSUES=$((TOMBSTONED_COUNT + DUPLICATE_COUNT))

echo ""
echo "========================================="
echo "📊 ANALYSIS SUMMARY"
echo "========================================="
echo "   Total device mapper entries: $TOTAL_DM_ENTRIES"
echo "   Valid entries: $VALID_DM_ENTRIES $([ "$VALID_DM_ENTRIES" -eq "$TOTAL_DM_ENTRIES" ] && echo "✅ ALL VALID!" || echo "")"
echo "   Duplicate entries: $DUPLICATE_COUNT $([ "$DUPLICATE_COUNT" -gt 0 ] && echo "🚨 CRITICAL ISSUE!" || echo "✅")"
echo "   Tombstoned entries: $TOMBSTONED_COUNT $([ "$TOMBSTONED_COUNT" -gt 0 ] && echo "⚠️ WILL BLOCK DISK CREATION!" || echo "✅")"
echo "   Total issues: $TOTAL_ISSUES"
echo ""
echo "   VMs on this node: $TOTAL_VMS ($RUNNING_VMS_COUNT running)"

if [ "$TOTAL_ISSUES" -eq 0 ]; then
    echo ""
    echo "🎉 EXCELLENT: No issues detected!"
    echo "   All device mapper entries are valid with no duplicates."
else
    echo ""
    if [ "$DUPLICATE_COUNT" -gt 0 ]; then
        echo "🚨 CRITICAL: $DUPLICATE_COUNT duplicate entries detected!"
        echo "   Duplicates cause unpredictable behavior and VM failures!"
    fi
    if [ "$TOMBSTONED_COUNT" -gt 0 ]; then
        echo "⚠️  WARNING: $TOMBSTONED_COUNT tombstoned entries detected!"
        echo "   Tombstones block VM disk creation operations!"
    fi
    echo ""
    echo "   IMMEDIATE ACTION REQUIRED: Run cleanup to fix these issues."
fi

# Show VM status details
echo ""
echo "========================================="
echo "🖥️  VM STATUS ON THIS NODE"
echo "========================================="
echo ""

if [ "$TOTAL_VMS" -gt 0 ]; then
    # Create a temp file to track VMs with issues
    VM_ISSUES_FILE=$(mktemp)
    VM_DUPLICATES_FILE=$(mktemp)
    
    # First, identify which existing VMs have tombstoned entries
    if [ -s "$TOMBSTONED_TEMP_FILE" ]; then
        while IFS= read -r line; do
            vm_id=$(echo "$line" | cut -d: -f2)
            # Only count if this VM exists on the node
            if echo "$ALL_VMS" | grep -q "^${vm_id}$"; then
                echo "$vm_id" >> "$VM_ISSUES_FILE"
            fi
        done < "$TOMBSTONED_TEMP_FILE"
    fi
    
    # Identify which VMs have duplicate entries
    if [ -s "$DUPLICATE_FILE" ]; then
        while IFS= read -r line; do
            vm_id=$(echo "$line" | cut -d: -f2)
            if echo "$ALL_VMS" | grep -q "^${vm_id}$"; then
                echo "$vm_id" >> "$VM_DUPLICATES_FILE"
            fi
        done < "$DUPLICATE_FILE"
    fi
    
    # Display VM list with status
    printf "%-8s %-40s %-12s %s\n" "VM ID" "NAME" "STATUS" "DM HEALTH"
    printf "%-8s %-40s %-12s %s\n" "-----" "----" "------" "---------"
    
    while IFS= read -r vm_line; do
        vm_id=$(echo "$vm_line" | awk '{print $1}')
        vm_name=$(echo "$vm_line" | awk '{$1=$2=""; print $0}' | xargs)
        vm_status=$(echo "$vm_line" | awk '{print $2}')
        
        # Check health status
        health_status="✅ Clean"
        
        # Check for duplicates (most critical)
        if [ -s "$VM_DUPLICATES_FILE" ] && grep -q "^${vm_id}$" "$VM_DUPLICATES_FILE"; then
            dup_count=$(grep "^DM:${vm_id}:" "$DUPLICATE_FILE" | wc -l)
            # Count unique storage:disk combinations with duplicates
            unique_storage_disks=$(grep "^DM:${vm_id}:" "$DUPLICATE_FILE" | cut -d: -f3,4 | sort -u | wc -l)
            health_status="🚨 $unique_storage_disks storage:disk(s) DUPLICATED!"
        # Check for tombstones
        elif [ -s "$VM_ISSUES_FILE" ] && grep -q "^${vm_id}$" "$VM_ISSUES_FILE"; then
            issue_count=$(grep -c "^DM:${vm_id}:" "$TOMBSTONED_TEMP_FILE" 2>/dev/null || echo "0")
            health_status="⚠️  $issue_count tombstone(s)"
        fi
        
        # Format status
        if [ "$vm_status" = "running" ]; then
            status_display="🟢 Running"
        else
            status_display="⚪ Stopped"
        fi
        
        printf "%-8s %-40s %-12s %s\n" "$vm_id" "${vm_name:0:40}" "$status_display" "$health_status"
    done < "$VM_LIST_FILE"
    
    rm -f "$VM_ISSUES_FILE" "$VM_DUPLICATES_FILE"
else
    echo "No VMs found on this node."
fi

# Show tombstoned entries for non-existent VMs
if [ "$TOMBSTONED_COUNT" -gt 0 ]; then
    # Count tombstones for VMs that don't exist
    NON_EXISTENT_TOMBSTONES=$(
        while IFS= read -r line; do
            vm_id=$(echo "$line" | cut -d: -f2)
            if ! echo "$ALL_VMS" | grep -q "^${vm_id}$"; then
                echo "$vm_id"
            fi
        done < "$TOMBSTONED_TEMP_FILE" | sort -u | wc -l
    )
    
    if [ "$NON_EXISTENT_TOMBSTONES" -gt 0 ]; then
        echo ""
        echo "Additionally, tombstones exist for $NON_EXISTENT_TOMBSTONES non-existent VM IDs:"
        while IFS= read -r line; do
            vm_id=$(echo "$line" | cut -d: -f2)
            if ! echo "$ALL_VMS" | grep -q "^${vm_id}$"; then
                echo "$vm_id"
            fi
        done < "$TOMBSTONED_TEMP_FILE" | sort -u | uniq -c | sort -nr | head -10 | while read count vm_id; do
            printf "   VM %-6s: %s tombstone(s) ❌ VM DOES NOT EXIST\n" "$vm_id" "$count"
        done
    fi
fi

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

# Get CPU usage
HOST_CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d. -f1)
if [ -z "$HOST_CPU_USAGE" ] || ! [[ "$HOST_CPU_USAGE" =~ ^[0-9]+$ ]]; then
    HOST_CPU_USAGE="0"
fi

HOST_SYSTEM_MODEL=$(dmidecode -s system-product-name 2>/dev/null || echo "Unknown")
HOST_ROOT_USAGE=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')
HOST_PRIMARY_NET=$(ip route | grep default | awk '{print $5}' | head -1)
HOST_NET_IP=$(ip -4 addr show $HOST_PRIMARY_NET 2>/dev/null | grep inet | awk '{print $2}' | head -1 || echo "N/A")
HOST_TOTAL_CTS=$(pct list 2>/dev/null | grep -v VMID | wc -l)
HOST_RUNNING_CTS=$(pct list 2>/dev/null | grep running | wc -l)

# Calculate health score
HEALTH_SCORE=100

# CRITICAL: Heavy penalties for duplicate entries (20 points per duplicate)
DUPLICATE_PENALTY=$((DUPLICATE_COUNT * 20))
[ $DUPLICATE_PENALTY -gt 60 ] && DUPLICATE_PENALTY=60
HEALTH_SCORE=$((HEALTH_SCORE - DUPLICATE_PENALTY))

# Moderate penalties for tombstoned entries (5 points per entry, max -40)
TOMBSTONE_PENALTY=$((TOMBSTONED_COUNT * 5))
[ $TOMBSTONE_PENALTY -gt 40 ] && TOMBSTONE_PENALTY=40
HEALTH_SCORE=$((HEALTH_SCORE - TOMBSTONE_PENALTY))

# Ensure score doesn't go below 0
[ $HEALTH_SCORE -lt 0 ] && HEALTH_SCORE=0

# Assign grade based on issues (duplicates are critical)
if [ $DUPLICATE_COUNT -gt 0 ]; then
    HEALTH_GRADE="F"
    HEALTH_COLOR="#dc3545"
elif [ $TOMBSTONED_COUNT -eq 0 ]; then
    HEALTH_GRADE="A+"
    HEALTH_COLOR="#28a745"
elif [ $TOMBSTONED_COUNT -le 5 ]; then
    HEALTH_GRADE="B"
    HEALTH_COLOR="#17a2b8"
elif [ $TOMBSTONED_COUNT -le 20 ]; then
    HEALTH_GRADE="C"
    HEALTH_COLOR="#ffc107"
elif [ $TOMBSTONED_COUNT -le 50 ]; then
    HEALTH_GRADE="D"
    HEALTH_COLOR="#fd7e14"
else
    HEALTH_GRADE="F"
    HEALTH_COLOR="#dc3545"
fi

echo "System metrics collected."

# Function to generate HTML email report
generate_html_email() {
    status_color=""
    status_text=""
    status_bg_color=""
    
    # Determine overall status
    if [ "$TOTAL_ISSUES" -eq 0 ]; then
        status_color="#155724"
        status_bg_color="#d4edda"
        status_text="HEALTHY"
    elif [ "$DUPLICATE_COUNT" -gt 0 ]; then
        status_color="#721c24"
        status_bg_color="#f8d7da"
        status_text="CRITICAL"
    elif [ "$TOMBSTONED_COUNT" -le 10 ]; then
        status_color="#856404"
        status_bg_color="#fff3cd"
        status_text="WARNING"
    else
        status_color="#721c24"
        status_bg_color="#f8d7da"
        status_text="CRITICAL"
    fi
    
    cat << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset='UTF-8'>
    <meta name='viewport' content='width=device-width, initial-scale=1.0'>
    <style>
        /* Reset and base styles */
        body { 
            font-family: 'Segoe UI', Arial, sans-serif; 
            line-height: 1.6; 
            color: #333; 
            margin: 0; 
            padding: 20px; 
            background-color: #f5f5f5;
            -webkit-text-size-adjust: 100%;
            -ms-text-size-adjust: 100%;
        }
        
        /* Container with responsive padding */
        .container { 
            max-width: 800px; 
            margin: 0 auto; 
            background-color: #fff; 
            border-radius: 8px; 
            box-shadow: 0 2px 4px rgba(0,0,0,0.1); 
            padding: 25px;
        }
        
        /* Headers with responsive sizing */
        .title-header { 
            background-color: #4f46e5; 
            color: white; 
            padding: 20px; 
            border-radius: 6px; 
            margin-bottom: 20px; 
            text-align: center; 
        }
        
        .section-header { 
            background-color: #495057; 
            color: white; 
            padding: 15px; 
            border-radius: 6px; 
            margin: 20px 0 15px 0; 
            text-align: center; 
        }
        
        h1 { 
            margin: 0; 
            font-size: 24px; 
            font-weight: bold; 
        }
        
        h3 { 
            margin: 0; 
            font-size: 18px; 
            font-weight: bold; 
        }
        
        /* Alert boxes */
        .alert { 
            background-color: #fff3cd; 
            color: #856404; 
            padding: 15px; 
            border-radius: 6px; 
            border-left: 4px solid #ffc107; 
            margin: 15px 0; 
        }
        
        .critical { 
            background-color: #f8d7da; 
            color: #721c24; 
            padding: 15px; 
            border-radius: 6px; 
            border-left: 4px solid #dc3545; 
            margin: 15px 0; 
        }
        
        .success { 
            background-color: #d4edda; 
            color: #155724; 
            padding: 15px; 
            border-radius: 6px; 
            border-left: 4px solid #28a745; 
            margin: 15px 0; 
        }
        
        /* Responsive metric grid */
        .metric-grid { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); 
            gap: 15px; 
            margin: 15px 0; 
        }
        
        .metric-item { 
            background-color: #f8f9fa; 
            padding: 15px; 
            border-radius: 6px; 
            border: 1px solid #dee2e6; 
        }
        
        .metric-label { 
            font-weight: bold; 
            color: #495057; 
            margin-bottom: 5px;
            font-size: 0.9em;
        }
        
        .metric-value { 
            color: #212529; 
            font-size: 1.1em;
            word-break: break-word;
        }
        
        /* General sections */
        .section { 
            margin: 20px 0; 
            padding: 15px; 
            background-color: #f9f9f9; 
            border-radius: 6px; 
            border: 1px solid #dee2e6; 
        }
        
        .explanation-box { 
            background-color: #e3f2fd; 
            color: #0d47a1; 
            padding: 15px; 
            border-radius: 6px; 
            border-left: 4px solid #2196f3; 
            margin: 15px 0; 
        }
        
        /* Responsive table */
        .table-wrapper {
            overflow-x: auto;
            -webkit-overflow-scrolling: touch;
            margin: 10px -15px;
            padding: 0 15px;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
            min-width: 400px;
        }
        
        thead tr {
            background-color: #f8f9fa;
            border-bottom: 2px solid #dee2e6;
        }
        
        th, td {
            text-align: left;
            padding: 8px;
            white-space: nowrap;
        }
        
        tbody tr {
            border-bottom: 1px solid #dee2e6;
        }
        
        /* Footer */
        .footer { 
            margin-top: 20px; 
            padding-top: 20px; 
            border-top: 1px solid #dee2e6; 
            color: #6c757d; 
            font-size: 0.9em;
            text-align: center;
        }
        
        .footer a { 
            color: #007bff; 
            text-decoration: none; 
        }
        
        .footer a:hover { 
            text-decoration: underline; 
        }
        
        /* Utility classes */
        .code-inline { 
            background-color: #e9ecef; 
            color: #212529; 
            padding: 2px 4px; 
            border-radius: 3px; 
            font-family: Courier New, monospace; 
            font-size: 0.9em;
            word-break: break-all;
        }
        
        .grade-badge { 
            display: inline-block; 
            padding: 4px 12px; 
            border-radius: 4px; 
            font-weight: bold; 
        }
        
        /* Mobile optimizations */
        @media screen and (max-width: 600px) {
            body {
                padding: 10px;
            }
            
            .container {
                padding: 15px;
                border-radius: 0;
                box-shadow: none;
            }
            
            .title-header,
            .section-header {
                padding: 12px;
                margin-bottom: 15px;
            }
            
            h1 {
                font-size: 20px;
            }
            
            h3 {
                font-size: 16px;
            }
            
            .alert,
            .critical,
            .success,
            .explanation-box {
                padding: 12px;
                font-size: 0.95em;
            }
            
            .metric-grid {
                grid-template-columns: 1fr 1fr;
                gap: 10px;
            }
            
            .metric-item {
                padding: 10px;
            }
            
            .metric-label {
                font-size: 0.85em;
            }
            
            .metric-value {
                font-size: 1em;
            }
            
            .section {
                padding: 12px;
                margin: 15px 0;
            }
            
            /* Make code blocks more readable on mobile */
            .code-inline {
                font-size: 0.85em;
                display: block;
                margin: 5px 0;
                padding: 8px;
            }
            
            /* Improve table scroll indicator */
            .table-wrapper {
                position: relative;
                box-shadow: inset -15px 0 15px -15px rgba(0,0,0,0.1);
            }
            
            th, td {
                font-size: 0.9em;
                padding: 6px;
            }
            
            /* Stack footer links on mobile */
            .footer p {
                margin: 5px 0;
            }
            
            .footer a {
                display: inline-block;
                margin: 2px 0;
            }
        }
        
        @media screen and (max-width: 400px) {
            .metric-grid {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class='container'>
        <div style='font-size: 0.9em; color: #6c757d; margin-bottom: 20px; border-bottom: 1px solid #dee2e6; padding-bottom: 10px;'>
EOF
    echo "            <p>Proxmox Device Mapper Issue Detection Report v35 - $(date '+%Y-%m-%d %H:%M:%S')</p>"
    echo "        </div>"
    echo "        "
    echo "        <div class='title-header' style='background-color: $([ "$TOMBSTONED_COUNT" -gt 20 ] && echo "#dc3545" || [ "$TOMBSTONED_COUNT" -gt 0 ] && echo "#ffc107" || echo "#28a745");'>"
    echo "            <h1>$(hostname) - DM Issue Report</h1>"
    echo "            <p style='margin: 10px 0 0 0; font-size: 14px; opacity: 0.9;'>Health Grade: <span class='grade-badge' style='background-color: rgba(255,255,255,0.2);'>$HEALTH_GRADE</span></p>"
    echo "        </div>"
    echo "        "
    
    if [ "$TOTAL_ISSUES" -gt 0 ]; then
        if [ "$DUPLICATE_COUNT" -gt 0 ]; then
            echo "        <div class='critical'>"
            echo "            <strong>🚨 CRITICAL ISSUE DETECTED:</strong>"
            echo "            <p style='margin: 10px 0 0 0; font-size: 1.1em;'><strong>$DUPLICATE_COUNT duplicate device mapper entries found!</strong></p>"
            echo "            <p style='margin: 5px 0 0 0;'>Duplicates cause unpredictable VM behavior and failures. IMMEDIATE cleanup required!</p>"
            if [ "$TOMBSTONED_COUNT" -gt 0 ]; then
                echo "            <p style='margin: 5px 0 0 0;'>Additionally: $TOMBSTONED_COUNT tombstoned entries will block disk creation.</p>"
            fi
        else
            echo "        <div class='alert'>"
            echo "            <strong>⚠️ WARNING:</strong> $TOMBSTONED_COUNT tombstoned entries detected"
            echo "            <p style='margin: 10px 0 0 0;'>These orphaned entries will cause 'Device busy' errors when creating VM disks.</p>"
        fi
        echo "            <p style='font-size: 0.9em; margin: 10px 0;'>Run cleanup: <span class='code-inline'>./Proxmox_DM_Cleanup_v35.sh</span></p>"
        echo "        </div>"
    else
        echo "        <div class='success'>"
        echo "            <strong>✅ EXCELLENT:</strong> No issues detected!"
        echo "            <p style='margin: 5px 0 0 0;'>All device mapper entries are valid with no duplicates or orphans.</p>"
        echo "        </div>"
    fi
    
    echo "        <div class='section-header'><h3>📊 Device Mapper Analysis</h3></div>"
    echo "        <div class='section'>"
    echo "            <div class='explanation-box'>"
    echo "                <strong>Critical Issues Detected:</strong><br>"
    echo "                • <strong>Duplicate entries:</strong> Multiple DM entries for the same VM disk - causes unpredictable behavior<br>"
    echo "                • <strong>Tombstoned entries:</strong> Orphaned DM entries for deleted VMs/disks - blocks disk creation"
    echo "            </div>"
    echo "            <div class='metric-grid'>"
    echo "                <div class='metric-item'>"
    echo "                    <div class='metric-label'>Total DM Entries</div>"
    echo "                    <div class='metric-value'>$TOTAL_DM_ENTRIES</div>"
    echo "                </div>"
    echo "                <div class='metric-item'>"
    echo "                    <div class='metric-label'>Valid Entries</div>"
    echo "                    <div class='metric-value' style='color: #28a745;'>$VALID_DM_ENTRIES</div>"
    echo "                </div>"
    echo "                <div class='metric-item'>"
    echo "                    <div class='metric-label'>Duplicate Entries</div>"
    echo "                    <div class='metric-value' style='color: $([ "$DUPLICATE_COUNT" -eq 0 ] && echo "#28a745" || echo "#dc3545");'>$DUPLICATE_COUNT $([ "$DUPLICATE_COUNT" -gt 0 ] && echo "🚨" || echo "")</div>"
    echo "                </div>"
    echo "                <div class='metric-item'>"
    echo "                    <div class='metric-label'>Tombstoned Entries</div>"
    echo "                    <div class='metric-value' style='color: $([ "$TOMBSTONED_COUNT" -eq 0 ] && echo "#28a745" || [ "$TOMBSTONED_COUNT" -le 20 ] && echo "#ffc107" || echo "#dc3545");'>$TOMBSTONED_COUNT</div>"
    echo "                </div>"
    echo "            </div>"
    
    if [ "$TOMBSTONED_COUNT" -gt 10 ]; then
        UNIQUE_VMS=$(awk -F: '{print $2}' "$TOMBSTONED_TEMP_FILE" | sort -u | wc -l)
        echo "            <div style='margin-top: 15px; padding: 10px; background-color: #ffebee; border-radius: 4px;'>"
        echo "                <strong style='color: #c62828;'>Impact Analysis:</strong>"
        echo "                <p style='margin: 5px 0 0 0; color: #c62828;'>$TOMBSTONED_COUNT tombstoned entries across $UNIQUE_VMS VM IDs will block disk creation operations.</p>"
        echo "            </div>"
    fi
    echo "        </div>"
    
    echo "        <div class='section-header'><h3>🖥️ VM Status on This Node</h3></div>"
    echo "        <div class='section'>"
    
    if [ "$TOTAL_VMS" -gt 0 ]; then
        echo "            <div class='table-wrapper'>"
        echo "            <table>"
        echo "                <thead>"
        echo "                    <tr>"
        echo "                        <th>VM ID</th>"
        echo "                        <th>Name</th>"
        echo "                        <th>Status</th>"
        echo "                        <th>DM Health</th>"
        echo "                    </tr>"
        echo "                </thead>"
        echo "                <tbody>"
        
        # Create a temp file to track VMs with issues
        VM_ISSUES_FILE=$(mktemp)
        VM_DUPLICATES_FILE=$(mktemp)
        
        # Identify which existing VMs have tombstoned entries
        if [ -s "$TOMBSTONED_TEMP_FILE" ]; then
            while IFS= read -r line; do
                vm_id=$(echo "$line" | cut -d: -f2)
                if echo "$ALL_VMS" | grep -q "^${vm_id}$"; then
                    echo "$vm_id" >> "$VM_ISSUES_FILE"
                fi
            done < "$TOMBSTONED_TEMP_FILE"
        fi
        
        # Identify which VMs have duplicate entries
        if [ -s "$DUPLICATE_FILE" ]; then
            while IFS= read -r line; do
                vm_id=$(echo "$line" | cut -d: -f2)
                if echo "$ALL_VMS" | grep -q "^${vm_id}$"; then
                    echo "$vm_id" >> "$VM_DUPLICATES_FILE"
                fi
            done < "$DUPLICATE_FILE"
        fi
        
        # Display each VM
        while IFS= read -r vm_line; do
            vm_id=$(echo "$vm_line" | awk '{print $1}')
            vm_name=$(echo "$vm_line" | awk '{$1=$2=""; print $0}' | xargs)
            vm_status=$(echo "$vm_line" | awk '{print $2}')
            
            # Check health - duplicates are most critical
            health_html=""
            row_style=""
            
            if [ -s "$VM_DUPLICATES_FILE" ] && grep -q "^${vm_id}$" "$VM_DUPLICATES_FILE"; then
                # Count unique storage:disk combinations with duplicates
                unique_storage_disks=$(grep "^DM:${vm_id}:" "$DUPLICATE_FILE" | cut -d: -f3,4 | sort -u | wc -l)
                health_html="<span style='color: #dc3545; font-weight: bold;'>🚨 $unique_storage_disks storage:disk(s) DUPLICATED!</span>"
                row_style="background-color: #ffebee;"
            elif [ -s "$VM_ISSUES_FILE" ] && grep -q "^${vm_id}$" "$VM_ISSUES_FILE"; then
                issue_count=$(grep -c "^DM:${vm_id}:" "$TOMBSTONED_TEMP_FILE" 2>/dev/null || echo "0")
                health_html="<span style='color: #dc3545; font-weight: bold;'>⚠️ $issue_count tombstone(s)</span>"
                row_style="background-color: #fff5f5;"
            else
                health_html="<span style='color: #28a745;'>✅ Clean</span>"
                row_style=""
            fi
            
            # Format status
            if [ "$vm_status" = "running" ]; then
                status_html="<span style='color: #28a745;'>🟢 Running</span>"
            else
                status_html="<span style='color: #6c757d;'>⚪ Stopped</span>"
            fi
            
            echo "                    <tr style='$row_style'>"
            echo "                        <td>$vm_id</td>"
            echo "                        <td>${vm_name:0:40}</td>"
            echo "                        <td>$status_html</td>"
            echo "                        <td>$health_html</td>"
            echo "                    </tr>"
        done < "$VM_LIST_FILE"
        
        echo "                </tbody>"
        echo "            </table>"
        echo "            </div>"
        
        rm -f "$VM_ISSUES_FILE" "$VM_DUPLICATES_FILE"
        
        # Show non-existent VM tombstones
        if [ "$TOMBSTONED_COUNT" -gt 0 ]; then
            NON_EXISTENT_TOMBSTONES=$(
                while IFS= read -r line; do
                    vm_id=$(echo "$line" | cut -d: -f2)
                    if ! echo "$ALL_VMS" | grep -q "^${vm_id}$"; then
                        echo "$vm_id"
                    fi
                done < "$TOMBSTONED_TEMP_FILE" | sort -u | wc -l
            )
            
            if [ "$NON_EXISTENT_TOMBSTONES" -gt 0 ]; then
                echo "            <div style='margin-top: 15px; padding: 10px; background-color: #ffebee; border-radius: 4px;'>"
                echo "                <strong style='color: #c62828;'>⚠️ Tombstones for Non-Existent VMs:</strong>"
                echo "                <p style='margin: 5px 0 0 0; color: #c62828;'>$NON_EXISTENT_TOMBSTONES VM IDs have tombstones but don't exist on this node. These will block future VMs from using these IDs.</p>"
                echo "            </div>"
            fi
        fi
    else
        echo "            <p style='color: #6c757d;'>No VMs found on this node.</p>"
    fi
    
    echo "        </div>"
    
    echo "        <div class='section-header'><h3>🖥️ System Information</h3></div>"
    echo "        <div class='section'><div class='metric-grid'>"
    echo "            <div class='metric-item'><div class='metric-label'>Proxmox Version</div><div class='metric-value'>$HOST_PROXMOX_VERSION</div></div>"
    echo "            <div class='metric-item'><div class='metric-label'>Uptime</div><div class='metric-value'>$HOST_UPTIME</div></div>"
    echo "            <div class='metric-item'><div class='metric-label'>CPU Usage</div><div class='metric-value'>${HOST_CPU_USAGE}%</div></div>"
    echo "            <div class='metric-item'><div class='metric-label'>RAM Usage</div><div class='metric-value'>$HOST_USED_RAM / $HOST_TOTAL_RAM (${HOST_RAM_PERCENT}%)</div></div>"
    echo "            <div class='metric-item'><div class='metric-label'>Virtual Machines</div><div class='metric-value'>$TOTAL_VMS total ($RUNNING_VMS_COUNT running)</div></div>"
    echo "            <div class='metric-item'><div class='metric-label'>Storage Usage</div><div class='metric-value'>$HOST_ROOT_USAGE</div></div>"
    echo "        </div></div>"
    
    if [ "$TOTAL_ISSUES" -gt 0 ]; then
        echo "        <div class='section'>"
        echo "            <div class='$([ "$DUPLICATE_COUNT" -gt 0 ] && echo "critical" || echo "alert")'>"
        echo "                <h3 style='margin: 0 0 15px 0;'>$([ "$DUPLICATE_COUNT" -gt 0 ] && echo "🚨 IMMEDIATE ACTION REQUIRED" || echo "⚠️ Action Recommended")</h3>"
        
        if [ "$DUPLICATE_COUNT" -gt 0 ]; then
            echo "                <p style='font-size: 1.1em; color: #dc3545;'><strong>CRITICAL: $DUPLICATE_COUNT duplicate device mapper entries detected!</strong></p>"
            echo "                <p><strong>Impact:</strong> Duplicates cause unpredictable VM behavior, potential data corruption, and startup failures.</p>"
        fi
        if [ "$TOMBSTONED_COUNT" -gt 0 ]; then
            echo "                <p><strong>$TOMBSTONED_COUNT Tombstoned Entries:</strong> These will cause 'Device busy' errors when creating VM disks.</p>"
        fi
        
        echo "                <p style='margin-top: 15px;'><strong>Fix now:</strong> SSH to $(hostname) and run:</p>"
                        echo "                <p style='margin: 5px 0; padding: 10px; background-color: #f8f9fa; border-radius: 4px; font-family: monospace;'>./Proxmox_DM_Cleanup_v35.sh</p>"
        echo "            </div>"
        echo "        </div>"
    else
        echo "        <div class='section'><div class='success'>"
        echo "            <h3 style='margin: 0 0 15px 0; color: #155724;'>✅ System Status: Excellent</h3>"
        echo "            <p>No issues found. Device mapper is properly synchronized with VM configurations.</p>"
        echo "            <p style='margin-top: 10px;'>All $TOTAL_DM_ENTRIES device mapper entries are valid with no duplicates.</p>"
        echo "        </div></div>"
    fi
    
    echo "        <div class='footer'>"
    echo "            <p><strong>ProxMox DM Issue Detector v35</strong></p>"
    echo "            <p>CRITICAL FIX: Storage pools now compared case-insensitively</p>"
    echo "            <p>Node: <strong>$(hostname)</strong> • Generated: $(date)</p>"
    echo "            <p><a href='https://github.com/keithrlucier/proxmox-dm-health-check'>📂 GitHub Repository</a> • <a href='https://github.com/keithrlucier/proxmox-dm-health-check/issues'>🐛 Report Issues</a></p>"
        echo "        </div>"
    echo "    </div>"
    echo "</body>"
    echo "</html>"
}

# Function to send email via Mailjet
send_mailjet_email() {
    html_content="$1"
    subject="$2"
    
    # CRITICAL FIX v34: Improved HTML escaping for JSON using python
    if command -v python3 >/dev/null 2>&1; then
        # Use python for proper JSON escaping
        json_payload=$(python3 -c "
import json, sys
html = '''$html_content'''
payload = {
    'Messages': [{
        'From': {'Email': '$FROM_EMAIL', 'Name': '$FROM_NAME'},
        'To': [{'Email': '$TO_EMAIL'}],
        'Subject': '''$subject''',
        'HTMLPart': html,
        'TextPart': 'Proxmox DM Issue Report for $(hostname) - $DUPLICATE_COUNT duplicate entries, $TOMBSTONED_COUNT tombstoned entries found.'
    }]
}
print(json.dumps(payload))
")
    else
        # Fallback to sed-based escaping
        html_escaped=$(echo "$html_content" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed "s/'/\\'/g" | tr '\n' ' ')
        json_payload="{\"Messages\":[{\"From\":{\"Email\":\"$FROM_EMAIL\",\"Name\":\"$FROM_NAME\"},\"To\":[{\"Email\":\"$TO_EMAIL\"}],\"Subject\":\"$subject\",\"HTMLPart\":\"$html_escaped\",\"TextPart\":\"Proxmox DM Issue Report for $(hostname) - $DUPLICATE_COUNT duplicate entries, $TOMBSTONED_COUNT tombstoned entries found.\"}]}"
    fi
    
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
echo "📧 EMAIL REPORTING"
echo "========================================="
echo ""
echo "Generating and sending HTML email report..."

# Generate email subject based on issues (duplicates are most critical)
if [ "$DUPLICATE_COUNT" -gt 0 ]; then
    email_subject="🚨 [$(hostname)] CRITICAL: $DUPLICATE_COUNT DUPLICATE DM entries causing VM failures! Grade: F"
elif [ "$TOMBSTONED_COUNT" -eq 0 ]; then
    email_subject="✅ [$(hostname)] Proxmox DM Health: EXCELLENT - Grade $HEALTH_GRADE (No issues)"
elif [ "$TOMBSTONED_COUNT" -le 10 ]; then
    email_subject="⚠️ [$(hostname)] Proxmox DM Health: $TOMBSTONED_COUNT tombstones detected - Grade $HEALTH_GRADE"
else
    email_subject="🚨 [$(hostname)] Proxmox DM WARNING: $TOMBSTONED_COUNT tombstones blocking VM operations - Grade $HEALTH_GRADE"
fi

# Generate and send email
html_report=$(generate_html_email)
if send_mailjet_email "$html_report" "$email_subject"; then
    echo "Email report delivered successfully!"
else
    echo "Email delivery failed. Report still available locally."
fi

# Interactive cleanup option
if [ "$TOTAL_ISSUES" -gt 0 ]; then
    echo ""
    echo "========================================="
    echo "🔧 INTERACTIVE CLEANUP OPTION"
    echo "========================================="
    echo ""
    
    echo "Found $TOTAL_ISSUES issues that need cleanup:"
    if [ "$DUPLICATE_COUNT" -gt 0 ]; then
        echo "  🚨 $DUPLICATE_COUNT DUPLICATE entries (CRITICAL - causes VM failures!)"
    fi
    if [ "$TOMBSTONED_COUNT" -gt 0 ]; then
        echo "  ⚠️  $TOMBSTONED_COUNT tombstoned entries (blocks disk creation)"
    fi
    echo ""
    
    if [ "$TOTAL_ISSUES" -gt 50 ]; then
        echo "⚠️  WARNING: You have $TOTAL_ISSUES total issues!"
        echo "   The interactive cleanup will prompt you for each one."
        echo ""
    fi
    
    echo "This script will exit in 30 seconds if no selection is made"
    read -t 30 -p "Do you want to interactively clean up these issues? (y/N): " cleanup_choice
    
    # Check if read timed out or user chose not to cleanup
    if [ $? -ne 0 ]; then
        echo ""
        echo "Timeout reached. Exiting without cleanup."
        exit 0
    fi
    
    if [[ $cleanup_choice =~ ^[Yy]$ ]]; then
        echo ""
        echo "Starting interactive cleanup..."
        echo "Priority: DUPLICATES first (critical), then tombstones"
        echo "Options: y=remove, n=skip, a=remove all remaining, q=quit"
        echo ""
        
        CLEANED_COUNT=0
        SKIPPED_COUNT=0
        REMOVE_ALL=false
        CURRENT_ENTRY=0
        
        # PRIORITY 1: Handle duplicate entries FIRST (most critical)
        if [ "$DUPLICATE_COUNT" -gt 0 ] && [ -s "$DUPLICATE_FILE" ]; then
            echo "========== PRIORITY 1: CLEANING DUPLICATE ENTRIES (CRITICAL!) =========="
            echo "⚠️  DUPLICATES CAUSE UNPREDICTABLE VM BEHAVIOR AND FAILURES!"
            echo ""
            
            # Process duplicates, keeping only the first occurrence for each VM:storage:disk combination
            awk -F: '{print $2":"$3":"$4}' "$DUPLICATE_FILE" | sort -u | while read vm_storage_disk; do
                vm_id=$(echo "$vm_storage_disk" | cut -d: -f1)
                storage=$(echo "$vm_storage_disk" | cut -d: -f2)
                disk_num=$(echo "$vm_storage_disk" | cut -d: -f3)
                
                echo "----------------------------------------"
                echo "🚨 DUPLICATE SET for VM $vm_id storage $storage disk-$disk_num:"
                echo ""
                
                # Get all entries for this VM+storage+disk
                FIRST_ENTRY=true
                grep "^DM:${vm_id}:${storage}:${disk_num}:" "$DUPLICATE_FILE" | while IFS= read -r dup_entry; do
                    dm_name=$(echo "$dup_entry" | cut -d: -f5)
                    
                    if [ "$FIRST_ENTRY" = "true" ]; then
                        echo "  ✅ KEEP: $dm_name (first entry)"
                        FIRST_ENTRY=false
                    else
                        CURRENT_ENTRY=$((CURRENT_ENTRY + 1))
                        
                        if [ "$REMOVE_ALL" = "true" ]; then
                            echo "  🗑️  Auto-removing duplicate: $dm_name"
                            if dmsetup remove "$dm_name" 2>/dev/null; then
                                echo "     ✓ Removed"
                                CLEANED_COUNT=$((CLEANED_COUNT + 1))
                            else
                                echo "     ✗ Failed"
                            fi
                        else
                            echo "  ❌ DUPLICATE: $dm_name"
                            echo ""
                            echo "  CRITICAL: This duplicate MUST be removed to prevent VM failures!"
                            echo ""
                            
                            read -p "Remove this duplicate? (y/n/a=all/q=quit) [STRONGLY RECOMMENDED: y]: " entry_choice </dev/tty
                            case $entry_choice in
                                [Yy]* | "") 
                                    echo "     Executing: dmsetup remove $dm_name"
                                    if dmsetup remove "$dm_name" 2>/dev/null; then
                                        echo "     ✓ SUCCESS: Removed duplicate"
                                        CLEANED_COUNT=$((CLEANED_COUNT + 1))
                                    else
                                        echo "     ✗ FAILED: Could not remove"
                                    fi
                                    ;;
                                [Nn]* ) 
                                    echo "     ⚠️  WARNING: Keeping duplicate - VM FAILURES LIKELY!"
                                    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                                    ;;
                                [Aa]* )
                                    echo "     REMOVE ALL: Will remove all remaining duplicates"
                                    REMOVE_ALL=true
                                    if dmsetup remove "$dm_name" 2>/dev/null; then
                                        echo "     ✓ SUCCESS: Removed duplicate"
                                        CLEANED_COUNT=$((CLEANED_COUNT + 1))
                                    else
                                        echo "     ✗ FAILED: Could not remove"
                                    fi
                                    ;;
                                [Qq]* ) 
                                    echo ""
                                    echo "CLEANUP STOPPED BY USER"
                                    break 3
                                    ;;
                                * ) 
                                    echo "     Invalid choice, skipping."
                                    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                                    ;;
                            esac
                        fi
                    fi
                done
                echo ""
            done
        fi
        
        # PRIORITY 2: Handle tombstoned entries
        if [ "$TOMBSTONED_COUNT" -gt 0 ] && [[ ! $entry_choice =~ ^[Qq]$ ]] && [ -s "$TOMBSTONED_TEMP_FILE" ]; then
            echo ""
            echo "========== PRIORITY 2: CLEANING TOMBSTONED ENTRIES =========="
            echo "These orphaned entries block VM disk creation"
            echo ""
            
            CURRENT_TOMBSTONE=0
            while IFS= read -r tombstone_line; do
                # Extract info from the line
                VM_ID=$(echo "$tombstone_line" | cut -d: -f2)
                STORAGE=$(echo "$tombstone_line" | cut -d: -f3)
                DISK_NUM=$(echo "$tombstone_line" | cut -d: -f4)
                DM_NAME=$(echo "$tombstone_line" | cut -d: -f5)
                REASON=$(echo "$tombstone_line" | cut -d: -f6-)
                
                CURRENT_TOMBSTONE=$((CURRENT_TOMBSTONE + 1))
                
                # If remove all is set, just remove without prompting
                if [ "$REMOVE_ALL" = "true" ]; then
                    echo "[$CURRENT_TOMBSTONE/$TOMBSTONED_COUNT] Auto-removing: $DM_NAME"
                    if dmsetup remove "$DM_NAME" 2>/dev/null; then
                        echo "  ✓ Removed"
                        CLEANED_COUNT=$((CLEANED_COUNT + 1))
                    else
                        echo "  ✗ Failed (may already be gone)"
                    fi
                    continue
                fi
                
                echo "----------------------------------------"
                echo "TOMBSTONE $CURRENT_TOMBSTONE of $TOMBSTONED_COUNT:"
                echo "  Device: $DM_NAME"
                echo "  VM ID: $VM_ID, Storage: $STORAGE, Disk: $DISK_NUM"
                echo "  Reason: $REASON"
                echo ""
                echo "  IMPACT: Blocks VM $VM_ID from creating disk-$DISK_NUM on storage $STORAGE"
                echo ""
                
                read -p "Remove this tombstone? (y/n/a=all/q=quit) [Recommended: y]: " entry_choice </dev/tty
                case $entry_choice in
                    [Yy]* | "") 
                        echo "  Executing: dmsetup remove $DM_NAME"
                        if dmsetup remove "$DM_NAME" 2>/dev/null; then
                            echo "  ✓ SUCCESS: Removed tombstone"
                            CLEANED_COUNT=$((CLEANED_COUNT + 1))
                        else
                            echo "  ✗ FAILED: Could not remove"
                        fi
                        ;;
                    [Nn]* ) 
                        echo "  ⚠️  Skipped (will continue blocking disk creation)"
                        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                        ;;
                    [Aa]* )
                        echo "  REMOVE ALL: Will remove all remaining entries"
                        REMOVE_ALL=true
                        if dmsetup remove "$DM_NAME" 2>/dev/null; then
                            echo "  ✓ SUCCESS: Removed tombstone"
                            CLEANED_COUNT=$((CLEANED_COUNT + 1))
                        else
                            echo "  ✗ FAILED: Could not remove"
                        fi
                        ;;
                    [Qq]* ) 
                        echo ""
                        echo "CLEANUP STOPPED BY USER"
                        break
                        ;;
                    * ) 
                        echo "  Invalid choice, skipping."
                        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                        ;;
                esac
            done < "$TOMBSTONED_TEMP_FILE"
        fi
        
        echo ""
        echo "========================================="
        echo "CLEANUP SUMMARY"
        echo "========================================="
        echo "Interactive cleanup completed:"
        echo "  • Cleaned: $CLEANED_COUNT issues"
        echo "  • Skipped: $SKIPPED_COUNT issues"
        
        if [ "$SKIPPED_COUNT" -gt 0 ]; then
            echo ""
            if grep -q "DUPLICATE" "$DUPLICATE_FILE" 2>/dev/null && [ "$SKIPPED_COUNT" -gt 0 ]; then
                echo "⚠️  CRITICAL WARNING: You skipped duplicate entries!"
                echo "   These WILL cause VM failures and unpredictable behavior!"
            else
                echo "⚠️  WARNING: $SKIPPED_COUNT issues remain!"
                echo "   These will continue to cause problems."
            fi
        fi
    else
        echo "Cleanup cancelled. No changes made."
    fi
fi

# Clean up temp files
rm -f "$DM_TEMP_FILE" "$CONFIG_TEMP_FILE" "$TOMBSTONED_TEMP_FILE" "$VALID_TEMP_FILE" "$DM_PARSED_FILE" "$VM_LIST_FILE" "$DUPLICATE_FILE" 2>/dev/null || true

echo ""
echo "Script completed."