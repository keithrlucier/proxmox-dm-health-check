#!/bin/bash
# VERSION 38 - Proxmox Device Mapper Issue Detector
# Updated HTML Design

# Mailjet Configuration
MAILJET_API_KEY="5555555555555"
MAILJET_API_SECRET="555555555555555555"
FROM_EMAIL="approvedsender@approveddomain.com"
FROM_NAME="ProxMox DM Issue Detector"
TO_EMAIL="target@email.com"

echo "Proxmox Device Mapper Issue Detector v37 - FIXED"
echo "Node: $(hostname)"
echo "Date: $(date)"
echo "Mode: DUPLICATE & TOMBSTONE DETECTION + OPTIONAL CLEANUP + EMAIL REPORTING"
echo ""
echo "IMPORTANT: This tool identifies critical device mapper issues:"
echo "           • DUPLICATES - Multiple DM entries for same disk (causes VM failures)"
echo "           • TOMBSTONES - Orphaned DM entries (blocks disk creation)"
echo "           • Device open safety check before removal"
echo ""

# Initialize count variables
TOTAL_DM_ENTRIES=0
VALID_DM_ENTRIES=0
TOMBSTONED_COUNT=0
DUPLICATE_COUNT=0
TOTAL_ISSUES=0
TOTAL_VMS=0
RUNNING_VMS_COUNT=0
DEVICES_IN_USE_COUNT=0

# Function to check if a device mapper device is currently open/in use
check_device_open() {
    local dm_name="$1"
    
    # Method 1: Check dmsetup info for open count
    local open_count=$(dmsetup info "$dm_name" 2>/dev/null | grep "Open count:" | awk '{print $3}')
    
    if [ -n "$open_count" ] && [ "$open_count" -gt 0 ]; then
        return 0  # Device is open
    fi
    
    # Method 2: Check if device exists in /dev/mapper and if it's being accessed
    if [ -e "/dev/mapper/$dm_name" ]; then
        # Check with lsof if available
        if command -v lsof >/dev/null 2>&1; then
            if lsof "/dev/mapper/$dm_name" 2>/dev/null | grep -q "/dev/mapper/$dm_name"; then
                return 0  # Device is open
            fi
        fi
        
        # Check with fuser if available
        if command -v fuser >/dev/null 2>&1; then
            if fuser -s "/dev/mapper/$dm_name" 2>/dev/null; then
                return 0  # Device is open
            fi
        fi
    fi
    
    return 1  # Device is not open
}

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

# Count running VMs for statistics - STATUS is in field 3!
RUNNING_VMS=""
while IFS= read -r vm_line; do
    vm_status=$(echo "$vm_line" | awk '{print $3}')  # FIELD 3, NOT 2!
    if [ "$vm_status" = "running" ]; then
        vm_id=$(echo "$vm_line" | awk '{print $1}')
        if [ -z "$RUNNING_VMS" ]; then
            RUNNING_VMS="$vm_id"
        else
            RUNNING_VMS="$RUNNING_VMS $vm_id"
        fi
        RUNNING_VMS_COUNT=$((RUNNING_VMS_COUNT + 1))
    fi
done < "$VM_LIST_FILE"

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
DEVICES_IN_USE_FILE=$(mktemp)

echo "$DM_ENTRIES" > "$DM_TEMP_FILE"
TOTAL_DM_ENTRIES=$(wc -l < "$DM_TEMP_FILE")

echo "Found $TOTAL_DM_ENTRIES device mapper entries to analyze"
echo ""

# Function to parse VM disk configuration - FIXED for local storage
parse_vm_config() {
    local vm_id="$1"
    local config_file="/etc/pve/qemu-server/${vm_id}.conf"
    
    if [ ! -f "$config_file" ]; then
        config_file="/etc/pve/local/qemu-server/${vm_id}.conf"
        if [ ! -f "$config_file" ]; then
            return 1
        fi
    fi
    
    # Extract ALL disk configurations
    grep -E "^(virtio|ide|scsi|sata|efidisk|tpmstate|nvme|mpath|unused)[0-9]+:" "$config_file" | while IFS= read -r line; do
        # Get the full disk definition after the first colon
        disk_def=$(echo "$line" | cut -d: -f2- | xargs)
        
        # Check if it contains a storage:disk pattern
        if echo "$disk_def" | grep -q ":"; then
            # Extract storage pool (before the first colon in the value)
            storage_pool=$(echo "$disk_def" | cut -d: -f1 | tr '[:upper:]' '[:lower:]')
            
            # Get everything after first colon
            disk_part=$(echo "$disk_def" | cut -d: -f2)
            
            # Extract disk number from patterns like vm-102-disk-0,cache=writeback...
            # Look specifically for vm-VMID-disk-NUM pattern
            if echo "$disk_part" | grep -E "vm-${vm_id}-(disk|cloudinit|tmp-state)-[0-9]+" >/dev/null; then
                # Extract just the disk number
                disk_num=$(echo "$disk_part" | sed -n "s/^vm-${vm_id}-\(disk\|cloudinit\|tmp-state\)-\([0-9]\+\).*/\2/p")
                
                if [ -n "$disk_num" ]; then
                    echo "CONFIG:${vm_id}:${storage_pool}:${disk_num}"
                fi
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
            # Extract storage pool by getting everything before 'vm--'
            STORAGE_PART=$(echo "$DM_NAME" | sed 's/-vm--.*//')
            
            # Convert double dashes back to single
            STORAGE_PART=$(echo "$STORAGE_PART" | sed 's/--/-/g')
            
            # Extract disk number
            DISK_NUM=$(echo "$DM_NAME" | sed -n 's/.*--disk--\([0-9]\+\).*/\1/p')
            
            if [ -z "$DISK_NUM" ]; then
                # Try alternative pattern for local storage
                DISK_NUM=$(echo "$DM_NAME" | sed -n 's/.*--\([0-9]\+\)$/\1/p')
            fi
            
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

# Debug: Show what we found in configs (remove in production)
if [ "$CONFIG_COUNT" -gt 0 ]; then
    echo "   Config entries found:"
    head -5 "$CONFIG_TEMP_FILE" | while read line; do
        echo "     $line"
    done
fi

# Parse all DM entries
echo ""
echo "Step 2: Analyzing device mapper entries..."
DM_PARSED_FILE=$(mktemp)
DUPLICATE_FILE=$(mktemp)
parse_dm_entries > "$DM_PARSED_FILE"

# Check for devices currently in use
echo ""
echo "Step 3: Checking device open status..."
while IFS= read -r dm_line; do
    if [[ "$dm_line" =~ ^DM: ]]; then
        DM_NAME=$(echo "$dm_line" | cut -d: -f5)
        if check_device_open "$DM_NAME"; then
            echo "$dm_line" >> "$DEVICES_IN_USE_FILE"
            DEVICES_IN_USE_COUNT=$((DEVICES_IN_USE_COUNT + 1))
        fi
    fi
done < "$DM_PARSED_FILE"
echo "   Found $DEVICES_IN_USE_COUNT devices currently in use"

# Check for DUPLICATES first
echo ""
echo "Step 4: Detecting DUPLICATE entries (critical issue!)..."
echo ""

awk -F: '{print $2":"$3":"$4}' "$DM_PARSED_FILE" | sort | uniq -c | while read count vm_storage_disk; do
    if [ "$count" -gt 1 ]; then
        vm_id=$(echo "$vm_storage_disk" | cut -d: -f1)
        storage=$(echo "$vm_storage_disk" | cut -d: -f2)
        disk_num=$(echo "$vm_storage_disk" | cut -d: -f3)
        
        echo "❌ CRITICAL DUPLICATE: VM $vm_id storage $storage disk-$disk_num has $count device mapper entries!"
        echo "   → This WILL cause unpredictable behavior and VM failures!"
        
        grep "^DM:${vm_id}:${storage}:${disk_num}:" "$DM_PARSED_FILE" | while IFS= read -r dup_line; do
            dm_name=$(echo "$dup_line" | cut -d: -f5)
            if grep -q "^${dup_line}$" "$DEVICES_IN_USE_FILE"; then
                echo "      - $dm_name [IN USE]"
            else
                echo "      - $dm_name"
            fi
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
echo "Step 5: Identifying tombstoned entries..."
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
            # VM exists, check if this disk is in its config
            DISK_IN_CONFIG=false
            
            # Look for exact match in config
            if grep -q "^CONFIG:${VM_ID}:${STORAGE}:${DISK_NUM}$" "$CONFIG_TEMP_FILE"; then
                DISK_IN_CONFIG=true
            else
                # CRITICAL: Handle Proxmox default storage mapping
                # "pve" in DM maps to "local-lvm" in config
                if [ "$STORAGE" = "pve" ]; then
                    if grep -q "^CONFIG:${VM_ID}:local-lvm:${DISK_NUM}$" "$CONFIG_TEMP_FILE"; then
                        DISK_IN_CONFIG=true
                    fi
                elif echo "$STORAGE" | grep -q "^local"; then
                    # Look for any local storage variant with same VM and disk num
                    if grep -E "^CONFIG:${VM_ID}:local[^:]*:${DISK_NUM}$" "$CONFIG_TEMP_FILE" | grep -q .; then
                        DISK_IN_CONFIG=true
                    fi
                fi
                
                # Also try matching without the storage prefix for some edge cases
                if [ "$DISK_IN_CONFIG" = "false" ]; then
                    # Check if there's ANY disk with this number for this VM
                    if grep -E "^CONFIG:${VM_ID}:[^:]+:${DISK_NUM}$" "$CONFIG_TEMP_FILE" | grep -q .; then
                        # Get the actual storage from config
                        CONFIG_STORAGE=$(grep -E "^CONFIG:${VM_ID}:[^:]+:${DISK_NUM}$" "$CONFIG_TEMP_FILE" | head -1 | cut -d: -f3)
                        # Compare normalized versions
                        if [ "$(echo "$CONFIG_STORAGE" | tr -d '-')" = "$(echo "$STORAGE" | tr -d '-')" ]; then
                            DISK_IN_CONFIG=true
                        fi
                    fi
                fi
            fi
            
            if [ "$DISK_IN_CONFIG" = "false" ]; then
                IS_TOMBSTONED=true
                TOMBSTONE_REASON="VM $VM_ID exists but has no disk-${DISK_NUM} on storage ${STORAGE} in config"
            fi
        fi
        
        if [ "$IS_TOMBSTONED" = "true" ]; then
            IN_USE_MSG=""
            if grep -q "^${dm_line}$" "$DEVICES_IN_USE_FILE"; then
                IN_USE_MSG=" [DEVICE IN USE]"
            fi
            echo "❌ TOMBSTONE: $DM_NAME$IN_USE_MSG"
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
echo "   Devices currently in use: $DEVICES_IN_USE_COUNT"
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
        # FIXED: Correct field extraction from qm list output
        # Format: VMID NAME STATUS ...
        vm_id=$(echo "$vm_line" | awk '{print $1}')
        vm_name=$(echo "$vm_line" | awk '{print $2}')     # NAME is field 2
        vm_status=$(echo "$vm_line" | awk '{print $3}')   # STATUS is field 3!
        
        # Check health status
        health_status="✅ Clean"
        
        # Check for duplicates (most critical)
        if [ -s "$VM_DUPLICATES_FILE" ] && grep -q "^${vm_id}$" "$VM_DUPLICATES_FILE"; then
            unique_storage_disks=$(grep "^DM:${vm_id}:" "$DUPLICATE_FILE" | cut -d: -f3,4 | sort -u | wc -l)
            health_status="🚨 $unique_storage_disks storage:disk(s) DUPLICATED!"
        # Check for tombstones
        elif [ -s "$VM_ISSUES_FILE" ] && grep -q "^${vm_id}$" "$VM_ISSUES_FILE"; then
            issue_count=$(grep -c "^DM:${vm_id}:" "$TOMBSTONED_TEMP_FILE" 2>/dev/null || echo "0")
            health_status="⚠️  $issue_count tombstone(s)"
        fi
        
        # Format status correctly
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

# Function to generate HTML email report - ENTERPRISE GRADE v38
generate_html_email() {
    # Determine status color and alert type
    local alert_bg_color=""
    local alert_border_color=""
    local alert_text_color=""
    local status_text=""
    
    if [ "$TOTAL_ISSUES" -eq 0 ]; then
        alert_bg_color="#f0fdf4"
        alert_border_color="#22c55e"
        alert_text_color="#166534"
        status_text="HEALTHY"
    elif [ "$DUPLICATE_COUNT" -gt 0 ]; then
        alert_bg_color="#fef2f2"
        alert_border_color="#ef4444"
        alert_text_color="#991b1b"
        status_text="CRITICAL"
    elif [ "$TOMBSTONED_COUNT" -le 10 ]; then
        alert_bg_color="#fef3c7"
        alert_border_color="#f59e0b"
        alert_text_color="#92400e"
        status_text="WARNING"
    else
        alert_bg_color="#fef2f2"
        alert_border_color="#ef4444"
        alert_text_color="#991b1b"
        status_text="CRITICAL"
    fi
    
    cat << EOF
<!DOCTYPE html>
<html lang="en" xmlns="http://www.w3.org/1999/xhtml" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <title>ProxMox DM Health Check - $(hostname)</title>
    
    <!--[if mso]>
    <noscript>
        <xml>
            <o:OfficeDocumentSettings>
                <o:PixelsPerInch>96</o:PixelsPerInch>
            </o:OfficeDocumentSettings>
        </xml>
    </noscript>
    <![endif]-->
</head>
<body style="margin: 0; padding: 0; word-spacing: normal; background-color: #f8fafc;">
    
    <!-- Email Wrapper -->
    <div role="article" aria-roledescription="email" aria-label="ProxMox Health Check" lang="en" style="text-size-adjust: 100%; -webkit-text-size-adjust: 100%; -ms-text-size-adjust: 100%;">
        
        <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%" style="background-color: #f8fafc;">
            <tr>
                <td align="center" style="padding: 40px 0;">
                    
                    <!--[if mso]>
                    <table role="presentation" align="center" cellspacing="0" cellpadding="0" border="0" width="600">
                    <tr>
                    <td>
                    <![endif]-->
                    
                    <!-- Email Container -->
                    <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%" style="max-width: 600px; margin: 0 auto; background-color: #ffffff; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);">
                        
                        <!-- Header -->
                        <tr>
                            <td>
                                <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%">
                                    <tr>
                                        <td style="background-color: #1e293b; padding: 24px; text-align: center;">
                                            <h1 style="color: #ffffff; font-size: 24px; font-weight: 700; margin: 0; letter-spacing: -0.5px; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;">ProxMox DM Health Check</h1>
                                        </td>
                                    </tr>
EOF

    # Add alert banner based on status
    if [ "$TOTAL_ISSUES" -gt 0 ]; then
        if [ "$DUPLICATE_COUNT" -gt 0 ]; then
            echo '                                    <tr>'
            echo '                                        <td style="background-color: #fef2f2; padding: 16px 24px; text-align: center; font-weight: 600; font-size: 14px; border-bottom: 2px solid #ef4444; color: #991b1b; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">'
            echo '                                            Critical Issue Detected'
            echo '                                        </td>'
            echo '                                    </tr>'
        else
            echo '                                    <tr>'
            echo '                                        <td style="background-color: #fef3c7; padding: 16px 24px; text-align: center; font-weight: 600; font-size: 14px; border-bottom: 2px solid #f59e0b; color: #92400e; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">'
            echo '                                            Warning Detected'
            echo '                                        </td>'
            echo '                                    </tr>'
        fi
    else
        echo '                                    <tr>'
        echo '                                        <td style="background-color: #f0fdf4; padding: 16px 24px; text-align: center; font-weight: 600; font-size: 14px; border-bottom: 2px solid #22c55e; color: #166534; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">'
        echo '                                            System Healthy'
        echo '                                        </td>'
        echo '                                    </tr>'
    fi
    
    echo '                                </table>'
    echo '                            </td>'
    echo '                        </tr>'
    echo '                        '
    echo '                        <!-- Main Content -->'
    echo '                        <tr>'
    echo '                            <td style="padding: 32px 24px; background-color: #ffffff;">'
    echo '                                '
    echo '                                <!-- Node & Grade Header -->'
    echo '                                <h2 style="color: #1a202c; font-size: 22px; font-weight: 600; line-height: 1.3; margin: 0 0 8px 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">Node: '$(hostname)'</h2>'
    echo '                                <p style="color: #64748b; font-size: 14px; margin: 0 0 24px 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">Health Grade: <span style="display: inline-block; padding: 4px 12px; border-radius: 4px; font-weight: bold; background-color: '$HEALTH_COLOR'; color: #ffffff;">'$HEALTH_GRADE'</span></p>'
    
    # Status Alert Box
    if [ "$TOTAL_ISSUES" -gt 0 ]; then
        echo '                                '
        echo '                                <!-- Alert Card -->'
        echo '                                <div style="background-color: '$alert_bg_color'; border: 1px solid #e2e8f0; border-radius: 8px; padding: 24px; margin: 16px 0; border-left: 4px solid '$alert_border_color';">'
        
        if [ "$DUPLICATE_COUNT" -gt 0 ]; then
            echo '                                    <h3 style="color: '$alert_text_color'; font-size: 18px; font-weight: 600; margin: 0 0 12px 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">Critical: Duplicate Device Mapper Entries</h3>'
            echo '                                    <p style="color: '$alert_text_color'; font-size: 16px; line-height: 1.6; margin: 0 0 8px 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;"><strong>'$DUPLICATE_COUNT' duplicate entries detected.</strong></p>'
            echo '                                    <p style="color: #475569; font-size: 14px; line-height: 1.6; margin: 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">Duplicates cause unpredictable VM behavior and failures. Immediate cleanup required.</p>'
            if [ "$TOMBSTONED_COUNT" -gt 0 ]; then
                echo '                                    <p style="color: #475569; font-size: 14px; line-height: 1.6; margin: 8px 0 0 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">Additionally: '$TOMBSTONED_COUNT' tombstoned entries will block disk creation.</p>'
            fi
        else
            echo '                                    <h3 style="color: '$alert_text_color'; font-size: 18px; font-weight: 600; margin: 0 0 12px 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">Warning: Tombstoned Entries Detected</h3>'
            echo '                                    <p style="color: '$alert_text_color'; font-size: 16px; line-height: 1.6; margin: 0 0 8px 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;"><strong>'$TOMBSTONED_COUNT' tombstoned entries detected.</strong></p>'
            echo '                                    <p style="color: #475569; font-size: 14px; line-height: 1.6; margin: 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">These orphaned entries will cause '"'"'Device busy'"'"' errors when creating VM disks.</p>'
        fi
        
        echo '                                </div>'
    else
        echo '                                '
        echo '                                <!-- Success Card -->'
        echo '                                <div style="background-color: #f0fdf4; border: 1px solid #e2e8f0; border-radius: 8px; padding: 24px; margin: 16px 0; border-left: 4px solid #22c55e;">'
        echo '                                    <h3 style="color: #166534; font-size: 18px; font-weight: 600; margin: 0 0 12px 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">System Status: Excellent</h3>'
        echo '                                    <p style="color: #475569; font-size: 14px; line-height: 1.6; margin: 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">All device mapper entries are valid with no duplicates or orphans.</p>'
        echo '                                </div>'
    fi
    
    # Device Mapper Analysis Section
    echo '                                '
    echo '                                <!-- Device Mapper Analysis -->'
    echo '                                <h3 style="background-color: #f8fafc; color: #1a202c; font-size: 16px; font-weight: 600; padding: 12px 16px; border-radius: 6px; margin: 24px 0 16px 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">Device Mapper Analysis</h3>'
    echo '                                '
    echo '                                <!-- Stats Grid -->'
    echo '                                <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%">'
    echo '                                    <tr>'
    echo '                                        <td valign="top" width="48%" style="padding-bottom: 16px;">'
    echo '                                            <div style="background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; padding: 20px; text-align: center;">'
    echo '                                                <p style="color: #64748b; font-size: 12px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; margin: 0 0 8px 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">Total Entries</p>'
    echo '                                                <p style="color: #1a202c; font-size: 32px; font-weight: 700; margin: 0; line-height: 1; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">'$TOTAL_DM_ENTRIES'</p>'
    echo '                                            </div>'
    echo '                                        </td>'
    echo '                                        <td width="4%">&nbsp;</td>'
    echo '                                        <td valign="top" width="48%" style="padding-bottom: 16px;">'
    echo '                                            <div style="background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; padding: 20px; text-align: center;">'
    echo '                                                <p style="color: #64748b; font-size: 12px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; margin: 0 0 8px 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">Valid Entries</p>'
    echo '                                                <p style="color: #22c55e; font-size: 32px; font-weight: 700; margin: 0; line-height: 1; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">'$VALID_DM_ENTRIES'</p>'
    echo '                                            </div>'
    echo '                                        </td>'
    echo '                                    </tr>'
    echo '                                    <tr>'
    echo '                                        <td valign="top" width="48%" style="padding-bottom: 16px;">'
    echo '                                            <div style="background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; padding: 20px; text-align: center;">'
    echo '                                                <p style="color: #64748b; font-size: 12px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; margin: 0 0 8px 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">Duplicate Entries</p>'
    echo '                                                <p style="color: '$([ "$DUPLICATE_COUNT" -eq 0 ] && echo "#22c55e" || echo "#ef4444")'; font-size: 32px; font-weight: 700; margin: 0; line-height: 1; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">'$DUPLICATE_COUNT'</p>'
    echo '                                            </div>'
    echo '                                        </td>'
    echo '                                        <td width="4%">&nbsp;</td>'
    echo '                                        <td valign="top" width="48%" style="padding-bottom: 16px;">'
    echo '                                            <div style="background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; padding: 20px; text-align: center;">'
    echo '                                                <p style="color: #64748b; font-size: 12px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; margin: 0 0 8px 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">Tombstoned</p>'
    echo '                                                <p style="color: '$([ "$TOMBSTONED_COUNT" -eq 0 ] && echo "#22c55e" || [ "$TOMBSTONED_COUNT" -le 20 ] && echo "#f59e0b" || echo "#ef4444")'; font-size: 32px; font-weight: 700; margin: 0; line-height: 1; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">'$TOMBSTONED_COUNT'</p>'
    echo '                                            </div>'
    echo '                                        </td>'
    echo '                                    </tr>'
    echo '                                </table>'
    
    # VM Status Table
    echo '                                '
    echo '                                <!-- VM Status -->'
    echo '                                <h3 style="background-color: #f8fafc; color: #1a202c; font-size: 16px; font-weight: 600; padding: 12px 16px; border-radius: 6px; margin: 24px 0 16px 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">Virtual Machine Status</h3>'
    
    if [ "$TOTAL_VMS" -gt 0 ]; then
        echo '                                '
        echo '                                <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%" style="border-collapse: collapse;">'
        echo '                                    <thead>'
        echo '                                        <tr style="background-color: #f8fafc; border-bottom: 2px solid #e2e8f0;">'
        echo '                                            <th align="left" style="padding: 12px 16px; font-size: 12px; font-weight: 600; color: #475569; text-transform: uppercase; letter-spacing: 0.5px; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">VM ID</th>'
        echo '                                            <th align="left" style="padding: 12px 16px; font-size: 12px; font-weight: 600; color: #475569; text-transform: uppercase; letter-spacing: 0.5px; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">Name</th>'
        echo '                                            <th align="left" style="padding: 12px 16px; font-size: 12px; font-weight: 600; color: #475569; text-transform: uppercase; letter-spacing: 0.5px; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">Status</th>'
        echo '                                            <th align="left" style="padding: 12px 16px; font-size: 12px; font-weight: 600; color: #475569; text-transform: uppercase; letter-spacing: 0.5px; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">Health</th>'
        echo '                                        </tr>'
        echo '                                    </thead>'
        echo '                                    <tbody>'
        
        # Create temp files to track VMs with issues
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
        ROW_INDEX=0
        while IFS= read -r vm_line; do
            vm_id=$(echo "$vm_line" | awk '{print $1}')
            vm_name=$(echo "$vm_line" | awk '{print $2}')
            vm_status=$(echo "$vm_line" | awk '{print $3}')
            
            # Determine row background
            ROW_BG=$((ROW_INDEX % 2))
            if [ "$ROW_BG" -eq 0 ]; then
                ROW_STYLE="background-color: #ffffff;"
            else
                ROW_STYLE="background-color: #f8fafc;"
            fi
            ROW_INDEX=$((ROW_INDEX + 1))
            
            # Check health status
            health_html=""
            if [ -s "$VM_DUPLICATES_FILE" ] && grep -q "^${vm_id}$" "$VM_DUPLICATES_FILE"; then
                unique_storage_disks=$(grep "^DM:${vm_id}:" "$DUPLICATE_FILE" | cut -d: -f3,4 | sort -u | wc -l)
                health_html='<span style="display: inline-block; padding: 4px 8px; font-size: 12px; font-weight: 600; line-height: 1; border-radius: 4px; background-color: #fef2f2; color: #991b1b;">'$unique_storage_disks' Duplicates</span>'
                ROW_STYLE="background-color: #fef2f2;"
            elif [ -s "$VM_ISSUES_FILE" ] && grep -q "^${vm_id}$" "$VM_ISSUES_FILE"; then
                issue_count=$(grep -c "^DM:${vm_id}:" "$TOMBSTONED_TEMP_FILE" 2>/dev/null || echo "0")
                health_html='<span style="display: inline-block; padding: 4px 8px; font-size: 12px; font-weight: 600; line-height: 1; border-radius: 4px; background-color: #fef3c7; color: #92400e;">'$issue_count' Tombstones</span>'
            else
                health_html='<span style="display: inline-block; padding: 4px 8px; font-size: 12px; font-weight: 600; line-height: 1; border-radius: 4px; background-color: #f0fdf4; color: #166534;">Clean</span>'
            fi
            
            # Format status
            if [ "$vm_status" = "running" ]; then
                status_html='<span style="display: inline-block; padding: 4px 8px; font-size: 12px; font-weight: 600; line-height: 1; border-radius: 4px; background-color: #f0fdf4; color: #166534;">Running</span>'
            else
                status_html='<span style="display: inline-block; padding: 4px 8px; font-size: 12px; font-weight: 600; line-height: 1; border-radius: 4px; background-color: #f1f5f9; color: #475569;">Stopped</span>'
            fi
            
            echo '                                        <tr style="'$ROW_STYLE' border-bottom: 1px solid #e2e8f0;">'
            echo '                                            <td style="padding: 12px 16px; font-size: 14px; color: #1a202c; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">'$vm_id'</td>'
            echo '                                            <td style="padding: 12px 16px; font-size: 14px; color: #1a202c; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">'${vm_name:0:40}'</td>'
            echo '                                            <td style="padding: 12px 16px; font-size: 14px; color: #1a202c; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">'$status_html'</td>'
            echo '                                            <td style="padding: 12px 16px; font-size: 14px; color: #1a202c; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">'$health_html'</td>'
            echo '                                        </tr>'
        done < "$VM_LIST_FILE"
        
        echo '                                    </tbody>'
        echo '                                </table>'
        
        rm -f "$VM_ISSUES_FILE" "$VM_DUPLICATES_FILE"
    else
        echo '                                <p style="color: #64748b; font-size: 14px; line-height: 1.5; margin: 8px 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">No VMs found on this node.</p>'
    fi
    
    # System Information
    echo '                                '
    echo '                                <!-- System Information -->'
    echo '                                <h3 style="background-color: #f8fafc; color: #1a202c; font-size: 16px; font-weight: 600; padding: 12px 16px; border-radius: 6px; margin: 24px 0 16px 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">System Information</h3>'
    echo '                                '
    echo '                                <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%" style="border: 1px solid #e2e8f0; border-radius: 8px; overflow: hidden;">'
    echo '                                    <tr style="border-bottom: 1px solid #e2e8f0;">'
    echo '                                        <td style="padding: 12px 16px; background-color: #f8fafc; font-size: 14px; font-weight: 600; color: #475569; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">Proxmox Version</td>'
    echo '                                        <td style="padding: 12px 16px; font-size: 14px; color: #1a202c; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">'$HOST_PROXMOX_VERSION'</td>'
    echo '                                    </tr>'
    echo '                                    <tr style="border-bottom: 1px solid #e2e8f0;">'
    echo '                                        <td style="padding: 12px 16px; background-color: #f8fafc; font-size: 14px; font-weight: 600; color: #475569; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">Uptime</td>'
    echo '                                        <td style="padding: 12px 16px; font-size: 14px; color: #1a202c; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">'$HOST_UPTIME'</td>'
    echo '                                    </tr>'
    echo '                                    <tr style="border-bottom: 1px solid #e2e8f0;">'
    echo '                                        <td style="padding: 12px 16px; background-color: #f8fafc; font-size: 14px; font-weight: 600; color: #475569; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">CPU Usage</td>'
    echo '                                        <td style="padding: 12px 16px; font-size: 14px; color: #1a202c; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">'${HOST_CPU_USAGE}'%</td>'
    echo '                                    </tr>'
    echo '                                    <tr style="border-bottom: 1px solid #e2e8f0;">'
    echo '                                        <td style="padding: 12px 16px; background-color: #f8fafc; font-size: 14px; font-weight: 600; color: #475569; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">RAM Usage</td>'
    echo '                                        <td style="padding: 12px 16px; font-size: 14px; color: #1a202c; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">'$HOST_USED_RAM' / '$HOST_TOTAL_RAM' ('${HOST_RAM_PERCENT}'%)</td>'
    echo '                                    </tr>'
    echo '                                    <tr style="border-bottom: 1px solid #e2e8f0;">'
    echo '                                        <td style="padding: 12px 16px; background-color: #f8fafc; font-size: 14px; font-weight: 600; color: #475569; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">Virtual Machines</td>'
    echo '                                        <td style="padding: 12px 16px; font-size: 14px; color: #1a202c; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">'$TOTAL_VMS' total ('$RUNNING_VMS_COUNT' running)</td>'
    echo '                                    </tr>'
    echo '                                    <tr>'
    echo '                                        <td style="padding: 12px 16px; background-color: #f8fafc; font-size: 14px; font-weight: 600; color: #475569; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">Storage Usage</td>'
    echo '                                        <td style="padding: 12px 16px; font-size: 14px; color: #1a202c; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">'$HOST_ROOT_USAGE'</td>'
    echo '                                    </tr>'
    echo '                                </table>'
    
    # Action Required Section (if issues exist)
    if [ "$TOTAL_ISSUES" -gt 0 ]; then
        echo '                                '
        echo '                                <!-- Call to Action -->'
        echo '                                <div style="text-align: center; margin: 32px 0;">'
        echo '                                    <h3 style="color: #1a202c; font-size: 18px; font-weight: 600; margin: 0 0 16px 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">Action Required</h3>'
        echo '                                    <p style="color: #475569; font-size: 14px; line-height: 1.6; margin: 0 0 20px 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">SSH to '$(hostname)' and run:</p>'
        echo '                                    <div style="background-color: #1e293b; color: #e2e8f0; padding: 16px; border-radius: 6px; font-family: '"'"'Courier New'"'"', monospace; font-size: 14px; margin: 0 0 20px 0;">./Proxmox_DM_Cleanup_v38.sh</div>'
        echo '                                    <table role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">'
        echo '                                        <tr>'
        echo '                                            <td>'
        echo '                                                <a href="ssh://root@'$(hostname)'" style="display: inline-block; padding: 12px 24px; font-size: 16px; font-weight: 600; text-decoration: none; border-radius: 6px; background-color: #2563eb; color: #ffffff; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">Connect to Node</a>'
        echo '                                            </td>'
        echo '                                        </tr>'
        echo '                                    </table>'
        echo '                                </div>'
    fi
    
    echo '                                '
    echo '                            </td>'
    echo '                        </tr>'
    echo '                        '
    echo '                        <!-- Footer -->'
    echo '                        <tr>'
    echo '                            <td>'
    echo '                                <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%">'
    echo '                                    <tr>'
    echo '                                        <td style="background-color: #f8fafc; padding: 32px 24px; text-align: center; border-top: 1px solid #e2e8f0;">'
    echo '                                            <p style="color: #64748b; font-size: 12px; line-height: 1.5; margin: 0 0 8px 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">ProxMox DM Health Check v38</p>'
    echo '                                            <p style="color: #64748b; font-size: 12px; line-height: 1.5; margin: 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">Generated: '$(date)'</p>'
    echo '                                            <p style="color: #64748b; font-size: 12px; line-height: 1.5; margin: 8px 0 0 0; font-family: -apple-system, BlinkMacSystemFont, '"'"'Segoe UI'"'"', Roboto, '"'"'Helvetica Neue'"'"', Arial, sans-serif;">Node: '$(hostname)'</p>'
    echo '                                        </td>'
    echo '                                    </tr>'
    echo '                                </table>'
    echo '                            </td>'
    echo '                        </tr>'
    echo '                        '
    echo '                    </table>'
    echo '                    '
    echo '                    <!--[if mso]>'
    echo '                    </td>'
    echo '                    </tr>'
    echo '                    </table>'
    echo '                    <![endif]-->'
    echo '                    '
    echo '                </td>'
    echo '            </tr>'
    echo '        </table>'
    echo '        '
    echo '    </div>'
    echo '</body>'
    echo '</html>'
}

# Function to send email via Mailjet
send_mailjet_email() {
    html_content="$1"
    subject="$2"
    
    # Improved HTML escaping for JSON using python
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
                        
                        # Check if device is open before attempting removal
                        if check_device_open "$dm_name"; then
                            echo "  ⚠️  DUPLICATE: $dm_name [DEVICE IS CURRENTLY OPEN/IN USE]"
                            echo "     → Cannot remove while device is in use. Stop the VM first."
                            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                            continue
                        fi
                        
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
                
                # Check if device is open before attempting removal
                if check_device_open "$DM_NAME"; then
                    echo "----------------------------------------"
                    echo "TOMBSTONE $CURRENT_TOMBSTONE of $TOMBSTONED_COUNT:"
                    echo "  Device: $DM_NAME [DEVICE IS CURRENTLY OPEN/IN USE]"
                    echo "  VM ID: $VM_ID, Storage: $STORAGE, Disk: $DISK_NUM"
                    echo "  Reason: $REASON"
                    echo ""
                    echo "  ⚠️  Cannot remove while device is in use!"
                    echo ""
                    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                    continue
                fi
                
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
rm -f "$DM_TEMP_FILE" "$CONFIG_TEMP_FILE" "$TOMBSTONED_TEMP_FILE" "$VALID_TEMP_FILE" "$DM_PARSED_FILE" "$VM_LIST_FILE" "$DUPLICATE_FILE" "$DEVICES_IN_USE_FILE" 2>/dev/null || true

echo ""
echo "Script completed."
