# Documentation: Proxmox Device Mapper Issue Detector (Version 30)

## Overview

The **Proxmox Device Mapper Issue Detector v30** is a comprehensive Bash-based tool designed to detect and resolve critical device mapper issues that cause VM failures in Proxmox Virtual Environment (PVE). The script's primary focus is identifying **duplicate device mapper entries** - the most critical issue that causes unpredictable VM behavior and startup failures.

**Key Focus Areas:**
- **DUPLICATE ENTRIES** (Critical): Multiple device mapper entries for the same VM disk
- **TOMBSTONED ENTRIES** (Warning): Orphaned entries for deleted VMs/disks that block future disk creation

The script performs real-time analysis, generates professional HTML reports with VM-specific health status, and delivers these reports via Mailjet email API. It includes a priority-based interactive cleanup mode for safe removal of problematic entries.

## Key Features

### Core Detection Features
- **Duplicate Detection** (Priority 1): Identifies multiple DM entries for the same VM disk
- **Tombstone Detection** (Priority 2): Finds orphaned DM entries that don't match any VM configuration
- **VM-Centric Analysis**: Shows health status for each VM on the node
- **Single-Pass Analysis**: No double-counting - each entry evaluated once

### VM Status Dashboard
- Lists all VMs on the node with their health status
- Shows which VMs have duplicate or tombstoned entries
- Visual indicators: 🚨 for duplicates, ⚠️ for tombstones, ✅ for clean
- Identifies non-existent VMs with lingering DM entries

### Reporting and Monitoring
- Professional HTML email reports with color-coded severity
- Health grading system (A+ to F) - any duplicates = automatic F grade
- System performance metrics and resource utilization
- Clear distinction between critical (duplicates) and warning (tombstones) issues

### Interactive Cleanup
- Priority-based cleanup: Duplicates first, then tombstones
- Detailed explanations for each issue type
- Safe removal process with user confirmation
- Option to auto-remove all remaining entries

## Critical Issues Explained

### 🚨 Duplicate Device Mapper Entries (CRITICAL)

**What are they?**
Multiple device mapper entries pointing to the same VM disk (e.g., two entries for `vm-169-disk-0`).

**Why are they critical?**
- Cause unpredictable VM behavior
- Can lead to data corruption
- Result in "Device or resource busy" errors
- Make VM operations unreliable

**Common causes:**
- Failed migration cleanup
- Storage operation interruptions
- Proxmox bugs during disk operations
- Manual storage manipulation

**Example:**
```
VM 169 config shows: scsi0: ssd-ha01:vm-169-disk-0
Device mapper has:
  - ssd--ha01-vm--169--disk--0  ✓ (correct)
  - ssd--ha01-vm--169--disk--0  ❌ (duplicate!)
```

### ⚠️ Tombstoned Entries (WARNING)

**What are they?**
Device mapper entries that exist but shouldn't - either the VM was deleted or the disk was removed from the VM's configuration.

**Why do they matter?**
- Block VM ID reuse (new VMs can't use those IDs)
- Prevent disk creation with conflicting names
- Waste system resources

**Common causes:**
- VMs deleted without proper cleanup
- Disks removed from VM config
- Failed restore operations
- Incomplete migrations

## Functions Breakdown

### 1. **VM Discovery and Analysis**
- Lists ALL VMs on the host (running and stopped)
- Retrieves VM names and current status
- Identifies which VMs have configuration issues

### 2. **Device Mapper Entry Analysis**
- Parses all DM entries matching `vm--<VMID>--disk` pattern
- Extracts VM ID, storage pool, and disk number
- Single-pass classification into:
  - **Valid**: Matches VM configuration exactly
  - **Duplicate**: Multiple entries for same VM+disk
  - **Tombstoned**: No matching VM or disk in config

### 3. **Duplicate Detection Algorithm**
- Groups DM entries by VM ID + disk number
- Identifies when count > 1 for any combination
- Marks all but first entry as duplicates
- Provides clear visual grouping in output

### 4. **VM Health Status Table**
Shows for each VM on the node:
- **VM ID**: Numeric identifier
- **Name**: VM's descriptive name
- **Status**: 🟢 Running or ⚪ Stopped
- **DM Health**: 
  - ✅ Clean
  - 🚨 X disk(s) DUPLICATED!
  - ⚠️ X tombstone(s)

### 5. **Health Grading System**
- **A+**: No issues found
- **B**: 1-5 tombstones only
- **C**: 6-20 tombstones only
- **D**: 21-50 tombstones only
- **F**: ANY duplicates OR 50+ tombstones

> **Note:** Duplicates automatically result in F grade due to their critical nature

### 6. **HTML Email Report**
Key sections include:
- Overall health status with grade
- Critical issues alert (duplicates highlighted)
- Device mapper analysis summary
- VM status table
- System information
- Action required section with cleanup instructions

### 7. **Priority-Based Interactive Cleanup**
Two-phase cleanup process:
1. **Priority 1 - Duplicates** (if any exist)
   - Shows which entry to keep (first)
   - Prompts to remove each duplicate
   - Strong warnings about impact
2. **Priority 2 - Tombstones** (if any exist)
   - Removes orphaned entries
   - Prevents future conflicts

## Installation

### 1. **Copy the script to the node**
```bash
scp Proxmox_DM_Cleanup_v30.sh root@<node-ip>:/root/
```

### 2. **Set execution permissions**
```bash
chmod +x /root/Proxmox_DM_Cleanup_v30.sh
```

### 3. **Run the script**
```bash
./Proxmox_DM_Cleanup_v30.sh
```

## Usage Examples

### Basic Analysis (Read-Only)
```bash
./Proxmox_DM_Cleanup_v30.sh
```
This performs analysis and sends an email report without making any changes.

### Interactive Cleanup
When issues are detected, the script offers interactive cleanup:
```
Do you want to interactively clean up these issues? (y/N): y
```

### Understanding the Output

#### VM Status Section
```
VM ID    NAME                           STATUS       DM HEALTH
-----    ----                           ------       ---------
169      Windows Server 2019            🟢 Running   🚨 2 disk(s) DUPLICATED!
170      Ubuntu 22.04                   ⚪ Stopped   ⚠️ 1 tombstone(s)
171      CentOS 8                       🟢 Running   ✅ Clean
```

#### Duplicate Detection Output
```
❌ CRITICAL DUPLICATE: VM 169 disk-0 has 2 device mapper entries!
   → This WILL cause unpredictable behavior and VM failures!
      - ssd--ha01-vm--169--disk--0
      - ssd--ha01-vm--169--disk--0
```

## Scheduling with Cron

To run automated checks daily at 10 PM:

```bash
crontab -e
```

Add this line:
```bash
0 22 * * * /root/Proxmox_DM_Cleanup_v30.sh > /var/log/proxmox_dm_check.log 2>&1
```

## Configuration

Edit these variables at the top of the script:

```bash
MAILJET_API_KEY="your-api-key"
MAILJET_API_SECRET="your-api-secret"
FROM_EMAIL="automation@yourdomain.com"
FROM_NAME="ProxMox DM Issue Detector"
TO_EMAIL="admin@yourdomain.com"
```

## Safety and Best Practices

### ✅ Safe by Design
- **Read-Only by Default**: No changes without explicit user consent
- **Priority-Based**: Critical issues (duplicates) handled first
- **Clear Explanations**: Each issue explained before action
- **No Data Loss**: Removes only device mapper entries, not actual disk data

### ⚠️ When to Run Cleanup
- **Immediately**: If duplicates are detected (critical issue)
- **Soon**: If many tombstones exist (blocks VM operations)
- **Maintenance Window**: For large-scale cleanup operations

### 🚨 What Gets Removed
- **Duplicates**: Extra device mapper entries (keeps first, removes others)
- **Tombstones**: Orphaned entries with no VM configuration
- **NOT Removed**: Actual disk data, VM configurations, or storage

## Common Scenarios and Solutions

### Scenario 1: VM Won't Start - "Device Busy" Error
**Cause**: Duplicate or tombstoned DM entries
**Solution**: Run script, clean duplicates/tombstones for that VM ID

### Scenario 2: Can't Create New VM with Specific ID
**Cause**: Tombstoned entries from previously deleted VM
**Solution**: Run script, remove tombstones for that VM ID

### Scenario 3: VM Behaving Unpredictably
**Cause**: Duplicate DM entries causing conflicts
**Solution**: Run script immediately, remove all duplicates

### Scenario 4: After Failed Migration
**Symptoms**: DM entries on source node after migration
**Solution**: Run script on source node, clean up tombstones

## Testing the Script

### Create Test Scenarios

#### Test Duplicate Detection
```bash
# Create a duplicate entry (use with caution!)
dmsetup create test--vm--999--disk--0 --table '0 204800 linear /dev/sda 0'
dmsetup create test--vm--999--disk--0-dup --table '0 204800 linear /dev/sda 0'
```

#### Test Tombstone Detection
```bash
# Create an orphaned entry
dmsetup create test--vm--888--disk--0 --table '0 204800 linear /dev/sda 0'
```

### Cleanup Test Entries
```bash
dmsetup remove test--vm--999--disk--0
dmsetup remove test--vm--999--disk--0-dup
dmsetup remove test--vm--888--disk--0
```

## Version 30 Key Improvements

### 🎯 Focus Shift
- **Primary Focus**: Duplicate detection (critical VM-breaking issue)
- **Secondary Focus**: Tombstone detection (blocks operations)
- **Removed**: Confusing "stale" terminology and double-counting

### 🆕 New Features
- **VM Status Dashboard**: Shows health for each VM on node
- **Duplicate Detection**: Identifies multiple DM entries per disk
- **Single-Pass Analysis**: Accurate counting without duplication
- **Priority Cleanup**: Handles critical issues first

### 🔧 Improvements
- **Clear Severity Levels**: Duplicates = Critical, Tombstones = Warning
- **Better Health Grading**: Duplicates = automatic F grade
- **Enhanced Email Subjects**: Clearly indicates issue severity
- **Simplified Terminology**: Valid, Duplicate, or Tombstoned only

### 📊 Better Reporting
- **VM-Centric View**: Focus on VMs rather than just entries
- **Visual Health Indicators**: 🚨, ⚠️, ✅ for quick assessment
- **Actionable Alerts**: Clear explanation of impact and solutions

## Troubleshooting

### Script Finds No VMs
- Verify you're running on a Proxmox node (not guest)
- Check `qm list` output manually
- Ensure proper permissions (run as root)

### Email Not Sending
- Verify Mailjet credentials
- Check network connectivity
- Review curl output for API errors

### Cleanup Fails
- Entry may already be removed
- Check `dmsetup ls` manually
- Some entries may require node reboot

## Summary

The Proxmox Device Mapper Issue Detector v30 fills a critical gap in Proxmox operations by identifying and resolving device mapper issues that cause VM failures. By focusing on duplicate detection as the primary concern, the script helps administrators maintain stable and predictable VM operations.

The tool is essential for:
- Clusters with frequent VM migrations
- Environments with high VM churn
- Recovery from failed operations
- Preventive maintenance
- Troubleshooting VM startup issues

Regular use of this script (via cron) provides early warning of developing issues and maintains a clean, efficient Proxmox environment.

**Remember**: Duplicates are critical and require immediate attention, while tombstones are important but less urgent. The script's priority-based approach ensures the most dangerous issues are addressed first.

---
**End of Documentation v30**