# Proxmox Device Mapper Health Check Documentation

## Executive Summary

The Proxmox Device Mapper Health Check is an enterprise-grade diagnostic and remediation tool designed to maintain the integrity of device mapper entries in Proxmox Virtual Environment (PVE) clusters. The tool identifies and resolves critical device mapper inconsistencies that can cause virtual machine failures, data corruption, and operational disruptions.

**Version 36 Enhancement**: Introduces device open safety checks to prevent removal of in-use device mapper entries, ensuring system stability during cleanup operations.

### Key Operational Context

In Proxmox VE:
- Device mapper entries are created when VMs start (intended behavior) or at system boot (bug in v8.2.2+)
- VM IDs are automatically assigned using the lowest available number from range 100-1,000,000 (configurable)
- When orphaned device mapper entries exist for a VM ID, they prevent Proxmox from reusing that ID
- System reboots do NOT clear orphaned entries - manual intervention is required

**Important Note**: Device mapper entries are intended to be automatically removed when VMs stop or are deleted. However, persistent bugs cause these entries to remain, creating the orphaned entry problem.

### Critical Known Issues

1. **Automatic Cleanup Failures**: Device mapper entries frequently fail to be removed when VMs are deleted
2. **Proxmox 8.2.2 Regression**: Creates device mapper entries for ALL LVM volumes at boot, not just active VMs
3. **Cluster Synchronization**: Shared storage environments may have orphaned entries on multiple nodes
4. **Race Conditions**: VM ID assignment lacks atomic reservation, causing conflicts during simultaneous VM creation

## System Architecture Overview

### Device Mapper in Proxmox

In Proxmox VE, the device mapper (DM) subsystem creates a mapping layer between virtual machine disk configurations and the underlying storage infrastructure. Each VM disk is represented by a device mapper entry that follows a specific naming convention:

```
<storage-pool>-vm--<vm-id>--disk--<disk-number>
```

For example:
- `ssd--ha01-vm--169--disk--0` represents disk 0 of VM 169 on storage pool ssd-ha01
- `t1--ha07-vm--119--disk--1` represents disk 1 of VM 119 on storage pool t1-ha07

### Problem Statement

Over time, device mapper entries can become desynchronized with VM configurations due to:
- Failed migration operations
- Incomplete VM deletions
- Storage detachment operations
- Cluster synchronization issues
- Manual intervention errors

These inconsistencies manifest as two primary issue types:

1. **Duplicate Entries**: Multiple device mapper entries pointing to the same VM disk on the same storage pool, causing unpredictable behavior and potential data corruption
2. **Orphaned Entries**: Device mapper entries that persist after their associated VM or disk has been removed, preventing resource reallocation

### Understanding Orphaned Entries

Orphaned device mapper entries require special attention as they represent a persistent system state issue:

**Definition**: An orphaned entry is a device mapper entry that exists in the kernel's device mapper table but has no corresponding active configuration. This includes:
- Entries for VMs that have been deleted
- Entries for VMs that exist in the cluster but are not configured to run on the current node
- Entries for disks that have been removed from a VM's configuration
- Entries remaining after failed migration operations

**Critical Characteristic**: Orphaned entries persist across system reboots. Restarting the host does NOT clear these entries because:
- Device mapper entries are recreated from persistent LVM metadata during boot
- The kernel rebuilds the device mapper table from stored configurations
- Only explicit removal using `dmsetup remove` will permanently delete these entries
- **Bug Alert**: Proxmox 8.2.2+ has a regression where ALL available LVM volumes get device mapper entries created at boot, regardless of VM state

**Root Causes of Orphaned Entries**:
- **Partition dependencies**: Child devices (e.g., vm-disk-0p1) keep parent devices open
- **LVM autoactivation**: In clustered environments, shared storage volumes are automatically activated on all nodes
- **Storage stack complexity**: GlusterFS, Ceph, and multipath configurations create intricate dependency chains
- **Cleanup failures**: The automatic removal process fails due to open file handles or improper deletion sequences
- **Version-specific bugs**: Proxmox 8.2.2 introduced boot-time creation of all LVM device mapper entries

**Impact on Operations**:
- **Automatic VM ID Reuse Conflicts**: Proxmox automatically assigns the lowest available VM ID when creating new VMs. If VM 119 is deleted while the highest VM ID is 180, the next VM created will automatically be assigned ID 119. If orphaned device mapper entries exist for VM 119, the new VM creation will fail with "device or resource busy" errors
- **Storage Allocation Conflicts**: Orphaned entries hold references to storage resources that appear allocated but are not actually in use
- **Migration Failures**: Orphaned entries can prevent VMs from migrating to a node if conflicting entries exist

**Important**: Device mapper entries persist for all configured VMs (running or stopped) and should match the VM's disk configuration. When entries exist without corresponding VM configurations, they become orphaned and block ID reuse.

**Note on Intended Behavior vs. Bugs**: 
- **Intended**: Device mapper entries should be created when VMs start and removed when they stop or are deleted
- **Actual**: Due to persistent bugs, entries often remain after VM deletion, creating orphaned entries
- **v8.2.2 Bug**: Creates device mapper entries for ALL LVM volumes at boot time, not just active VMs

## Core Logic and Workflow

### 1. Discovery Phase

The script begins by performing comprehensive system discovery:

```
VM Discovery:
├── Query all VMs on the current node (qm list)
├── Extract VM IDs, names, and running states
├── Count total and running VMs
└── Store VM metadata for reference
```

### 2. Device Mapper Analysis

The analysis phase examines all device mapper entries:

```
DM Entry Analysis:
├── List all device mapper entries (dmsetup ls)
├── Filter VM-related entries (pattern: vm--[0-9]+--disk)
├── Parse each entry to extract:
│   ├── Storage pool name
│   ├── VM ID
│   └── Disk number
└── Build comprehensive mapping table
```

### 3. Device Open Safety Check (NEW in v36)

Before any analysis or remediation, the tool now performs device open status verification:

```
Device Open Check:
├── For each device mapper entry:
│   ├── Query open count via dmsetup info
│   ├── Check for file handles using lsof (if available)
│   ├── Verify with fuser (if available)
│   └── Mark devices as "IN USE" if open
├── Track total devices in use
└── Store open status for cleanup safety
```

#### Device Open Detection Methods

The tool uses multiple methods to ensure accurate detection of in-use devices:

1. **Primary Method - dmsetup info**:
   ```bash
   dmsetup info <device-name> | grep "Open count:"
   ```
   - Returns the number of open references to the device
   - Most reliable method for device mapper entries

2. **Secondary Method - lsof**:
   ```bash
   lsof /dev/mapper/<device-name>
   ```
   - Identifies processes with open file handles
   - Provides additional validation

3. **Tertiary Method - fuser**:
   ```bash
   fuser /dev/mapper/<device-name>
   ```
   - Quick check for device usage
   - Fallback when lsof is unavailable

### 4. Configuration Validation

Each VM's configuration is parsed to build the expected device mapper state:

```
Configuration Parsing:
├── Read VM configuration files (/etc/pve/qemu-server/<vmid>.conf)
├── Extract all disk definitions:
│   ├── Standard disks (virtio, ide, scsi, sata)
│   ├── Special disks (efidisk, tpmstate)
│   ├── Modern disks (nvme, mpath)
│   └── Unused disk reservations
├── Normalize storage pool names (case-insensitive)
└── Create expected DM entry list
```

### 5. Issue Detection Algorithm

#### Duplicate Detection Logic

```python
# Pseudocode for duplicate detection
for each unique (vm_id, storage_pool, disk_number):
    entry_count = count_matching_dm_entries()
    if entry_count > 1:
        mark_as_duplicate(all_but_first_entry)
        set_severity = CRITICAL
        # NEW in v36: Note which duplicates are in use
        for each duplicate_entry:
            if is_device_open(duplicate_entry):
                mark_as_in_use()
```

Duplicates are identified when multiple device mapper entries exist for the same combination of:
- VM ID
- Storage pool
- Disk number

**Important**: Different storage pools with the same disk number are valid configurations (e.g., disk-0 on both ssd-ha01 and ssd-ha07).

#### Orphan Detection Logic

```python
# Pseudocode for orphan detection
for each dm_entry:
    if vm_id not in active_vms_on_this_node:
        mark_as_orphan("VM does not exist on this node")
    elif (vm_id, storage_pool, disk_num) not in vm_configurations:
        mark_as_orphan("Disk not in VM configuration")
    # NEW in v36: Check if orphan is in use
    if is_orphan and is_device_open(dm_entry):
        mark_as_in_use_orphan()
```

Orphaned entries are identified when:
- The VM ID does not exist on the current node (it may exist elsewhere in the cluster)
- The VM exists on the node but has no corresponding disk on the specified storage pool
- The disk reference was removed from the VM configuration but the mapper entry persists

**Important**: A VM may exist in the Proxmox cluster on a different node, but if it's not configured to run on the current node, its device mapper entries are considered orphaned on this node.

### 6. Health Assessment

The system calculates a comprehensive health score:

```
Health Score Calculation:
├── Base score: 100 points
├── Deductions:
│   ├── Duplicate entries: -20 points each (max -60)
│   └── Orphaned entries: -5 points each (max -40)
└── Grade assignment:
    ├── A+: No issues detected
    ├── B:  1-5 orphaned entries
    ├── C:  6-20 orphaned entries
    ├── D:  21-50 orphaned entries
    └── F:  Any duplicates OR 50+ orphaned entries
```

**NEW in v36**: The health assessment now includes device open status information:
- Total devices currently in use
- Which problematic entries cannot be immediately cleaned
- Safety warnings for cleanup operations

### 7. Reporting Engine

The reporting system generates comprehensive HTML reports including:

- **Executive Summary**: Overall health status and grade
- **Issue Analysis**: Detailed breakdown of detected problems
- **VM Status Matrix**: Health status for each VM
- **System Metrics**: CPU, memory, storage utilization
- **Device Open Status** (NEW): Count and identification of in-use devices
- **Remediation Guidance**: Specific cleanup instructions with safety warnings

### 8. Enhanced Remediation Workflow (v36)

The cleanup process now includes comprehensive safety checks:

```
Safe Cleanup Priority:
1. Critical Issues (Duplicates)
   ├── Display all duplicates grouped by VM/storage/disk
   ├── Check device open status for each duplicate
   ├── Skip devices marked as [DEVICE IS CURRENTLY OPEN/IN USE]
   ├── Preserve first entry (original)
   ├── Remove only safe duplicates
   └── Log skipped devices with explanations

2. Warning Issues (Orphans)
   ├── Display orphaned entries with reasons
   ├── Check device open status for each orphan
   ├── Skip devices marked as [DEVICE IS CURRENTLY OPEN/IN USE]
   ├── Show impact (will block automatic VM ID reuse)
   ├── Remove only safe orphaned entries
   └── Log skipped devices with explanations
```

#### Safety Features in Cleanup

1. **Pre-removal Check**: Every device is checked for open status before removal attempt
2. **Automatic Skip**: Devices in use are automatically skipped with clear messaging
3. **VM Protection**: Running VMs' devices are protected from accidental removal
4. **Clear Warnings**: Users are informed why specific devices cannot be removed
5. **No Force Option**: The tool never forces removal of open devices

Example cleanup interaction with safety check:
```
----------------------------------------
🚨 DUPLICATE SET for VM 169 storage ssd-ha01 disk-0:

  ✅ KEEP: ssd--ha01-vm--169--disk--0 (first entry)
  ⚠️  DUPLICATE: ssd--ha01-vm--169--disk--0-copy [DEVICE IS CURRENTLY OPEN/IN USE]
     → Cannot remove while device is in use. Stop the VM first.
  ❌ DUPLICATE: ssd--ha01-vm--169--disk--0-old

Remove this duplicate? (y/n/a=all/q=quit) [STRONGLY RECOMMENDED: y]:
```

## Technical Implementation Details

### Device Open Safety Implementation (v36)

The `check_device_open()` function implements a multi-layered approach:

```bash
check_device_open() {
    local dm_name="$1"
    
    # Method 1: Check dmsetup info for open count
    local open_count=$(dmsetup info "$dm_name" 2>/dev/null | grep "Open count:" | awk '{print $3}')
    
    if [ -n "$open_count" ] && [ "$open_count" -gt 0 ]; then
        return 0  # Device is open
    fi
    
    # Method 2: Check if device exists and is being accessed
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
```

### Storage Pool Name Resolution

The tool handles storage pool naming complexities:

1. **Device Mapper Conversion**: Single hyphens in storage names become double hyphens in DM
   - Storage: `ssd-ha01` → DM: `ssd--ha01`
   - Storage: `t1-ha07` → DM: `t1--ha07`

2. **Case Normalization**: All comparisons are case-insensitive
   - Config: `SSD-HA01` matches DM: `ssd--ha01`
   - Config: `T1-HA07` matches DM: `t1--ha07`

### Disk Type Recognition

Supported disk types include:
- **Traditional**: virtio, ide, scsi, sata
- **Special Purpose**: efidisk, tpmstate
- **Modern**: nvme, mpath
- **Reserved**: unused

### Safety Mechanisms

1. **Read-Only Default**: Analysis only, no modifications without explicit consent
2. **Confirmation Prompts**: Each removal action requires user confirmation
3. **Batch Operations**: Option to approve all remaining actions
4. **Graceful Exit**: Cleanup can be cancelled at any point
5. **Device Open Protection** (NEW): Prevents removal of in-use devices
6. **Running VM Protection** (NEW): Automatically skips devices belonging to running VMs

## Deployment and Usage

### When to Run This Tool

1. **After VM Deletions**: Since Proxmox automatically reuses the lowest available VM ID, run cleanup after deleting VMs to prevent future creation failures

2. **When VM Creation Fails**: If you encounter "device or resource busy" errors when creating a new VM, orphaned entries are blocking Proxmox's automatic ID assignment

3. **Regular Maintenance**: Schedule periodic runs to prevent accumulation of orphaned entries

4. **After Failed Operations**: Following failed migrations, incomplete deletions, or storage detachments

5. **Before Major Operations** (NEW): Run analysis to identify devices in use before planning maintenance

### Installation

```bash
# Download the latest version
wget https://raw.githubusercontent.com/keithrlucier/proxmox-dm-health-check/main/Proxmox_DM_Cleanup_v36.sh

# Set execution permissions
chmod +x Proxmox_DM_Cleanup_v36.sh
```

### VM ID Assignment Configuration

VM IDs can be configured at: **Datacenter → Options → "Next free VMID range"**

Default range: **100 to 1,000,000** (modern Proxmox supports up to 999,999,999)

Configuration file: `/etc/pve/datacenter.cfg`

CLI configuration:
```bash
pvesh set /cluster/options --next-id lower=100,upper=999999
```

### Configuration

Edit the script header to configure email notifications:

```bash
# Mailjet Configuration
MAILJET_API_KEY="your-api-key"
MAILJET_API_SECRET="your-api-secret"
FROM_EMAIL="noc@company.com"
FROM_NAME="Proxmox Health Monitor"
TO_EMAIL="infrastructure-team@company.com"
```

### Execution Modes

#### 1. Analysis Only (Default)
```bash
./Proxmox_DM_Cleanup_v36.sh
```
Performs analysis and sends report without modifications.

#### 2. Interactive Cleanup
When prompted after analysis:
```
Do you want to interactively clean up these issues? (y/N): y
```

#### 3. Automated Monitoring
Add to crontab for daily checks:
```bash
0 2 * * * /root/Proxmox_DM_Cleanup_v36.sh > /var/log/proxmox_dm_check.log 2>&1
```

## Output Interpretation

### Console Output Structure (Enhanced in v36)

```
========================================
ANALYSIS SUMMARY
========================================
   Total device mapper entries: 487
   Valid entries: 481
   Duplicate entries: 2 [CRITICAL ISSUE]
   Tombstoned entries: 4 [WARNING]
   Devices currently in use: 3
   Total issues: 6

   VMs on this node: 45 (42 running)
```

### VM Status Report

```
VM ID    NAME                           STATUS       DM HEALTH
-----    ----                           ------       ---------
169      Production Database            Running      [!] 1 storage:disk(s) DUPLICATED
170      Web Server                     Running      Clean
171      Backup Server                  Stopped      [!] 2 tombstone(s)
```

### Device Status Indicators (NEW in v36)

During analysis and cleanup, devices show their open status:
- `[IN USE]` - Device is currently open and cannot be removed
- `[DEVICE IS CURRENTLY OPEN/IN USE]` - Detailed warning during cleanup
- No indicator - Device is safe to remove

### Email Report Components

The HTML email report includes:

1. **Header Section**
   - Node identification
   - Timestamp
   - Overall health grade

2. **Issue Summary**
   - Critical issues requiring immediate attention
   - Warning issues affecting operations
   - Detailed impact analysis
   - **Device open status summary** (NEW)

3. **System Metrics**
   - Resource utilization
   - VM statistics
   - Storage usage
   - **Devices in use count** (NEW)

4. **Remediation Instructions**
   - Specific commands to execute
   - Expected outcomes
   - Safety considerations
   - **Device availability warnings** (NEW)

## Best Practices

### Operational Guidelines

1. **Regular Monitoring**
   - Schedule daily automated checks
   - Review reports for trending issues
   - Address critical issues immediately
   - Monitor devices in use patterns

2. **Maintenance Windows**
   - Perform cleanup during scheduled maintenance
   - Ensure recent backups exist
   - Document all remediation actions
   - **Stop affected VMs before cleanup** (NEW recommendation)

3. **Cluster Coordination**
   - Run on all nodes sequentially
   - Coordinate with migration operations
   - Monitor cluster-wide health trends
   - **Check device status before migrations** (NEW)

4. **Understanding Orphaned Entry Persistence**
   - Remember that orphaned entries survive system reboots
   - Do not rely on reboots to clear device mapper issues
   - Plan for explicit cleanup as part of maintenance procedures
   - Consider running cleanup after major cluster operations (migrations, deletions)

### VM Lifecycle Management

To minimize orphaned entries:

1. **VM Deletion Process**
   - Always use proper Proxmox VM deletion commands
   - Run this cleanup tool immediately after VM deletions
   - Understand that Proxmox will reuse the deleted VM's ID for the next VM creation
   - **Ensure VMs are stopped before deletion** (NEW emphasis)

2. **VM Creation Process**
   - Be aware that Proxmox automatically assigns the lowest available VM ID
   - If VM creation fails with "device busy" errors, orphaned entries are likely present
   - Run cleanup before creating new VMs if previous VMs were deleted

3. **VM Migration Process**
   - Check source node for orphaned entries after migration
   - Clean up any remaining entries on the source node
   - Document which nodes have hosted specific VMs
   - **Verify no devices are in use before migration** (NEW)

4. **Understanding Device Mapper Behavior**
   - Device mapper entries are created when VMs start (normal) or at boot (v8.2.2+ bug)
   - Entries SHOULD be automatically removed when VMs stop/delete (but often aren't due to bugs)
   - Entries persist for the lifetime of the VM (whether running or stopped) until properly cleaned
   - Orphaned entries occur when VM deletion or disk removal doesn't properly clean up the device mapper
   - Orphaned entries will conflict with Proxmox's automatic ID assignment
   - **Devices remain open while VMs are running** (NEW insight)
   - **Known Issues**: 
     - Automatic cleanup frequently fails, especially with partition tables or complex storage
     - Proxmox 8.2.2+ creates entries for all LVM volumes at boot, increasing orphaned entries
     - Running VMs keep device mapper entries open, preventing cleanup

### Risk Mitigation

1. **Pre-Cleanup Validation**
   - Verify VM backups are current
   - Document existing issues
   - Test in non-production environment
   - **Critical Check**: Ensure device "Open count" is 0 before removal (use `dmsetup info <device>`)
   - **NEW**: Tool now performs this check automatically

2. **During Cleanup**
   - Review each action carefully
   - Monitor system logs
   - Be prepared to halt if unexpected behavior occurs
   - **Order Matters**: Remove child devices (e.g., vm-disk-0p1) before parent devices (vm-disk-0)
   - **NEW**: Tool automatically skips open devices, preventing errors

3. **Post-Cleanup Verification**
   - Verify VM functionality
   - Check storage accessibility
   - Run analysis to confirm resolution
   - **Verify no devices remain unexpectedly open** (NEW)

### Preventive Configuration

**LVM Filter Configuration** (prevents VM disks from being scanned):
```bash
# Edit /etc/lvm/lvm.conf
global_filter = ["r|/dev/zd.*|", "r|/dev/mapper/.*-vm--[0-9]+--disk--[0-9]+|"]
```

**Disable Autoactivation** (for clustered shared storage):
```bash
vgchange <VG_NAME> --setautoactivation n
```

## Troubleshooting Guide

### Common Issues and Solutions

#### No VMs Detected
- **Cause**: Script run on wrong system or insufficient permissions
- **Solution**: Verify execution on Proxmox node as root user

#### Email Delivery Failure
- **Cause**: Invalid Mailjet credentials or network issues
- **Solution**: Verify API credentials and network connectivity

#### Cleanup Operation Fails
- **Cause**: Device mapper entry already removed or locked
- **Solution**: Verify entry exists with `dmsetup ls` command

#### Device Cannot Be Removed (NEW in v36)
- **Cause**: Device is currently open/in use by a running VM or process
- **Solution**: Stop the VM using the device, then retry cleanup
- **Prevention**: The tool now automatically detects and skips these devices

#### High Number of Orphaned Entries
- **Cause**: Improper VM deletion procedures or cluster migrations
- **Solution**: Review and update VM lifecycle management procedures

#### Orphaned Entries Persist After Reboot
- **Cause**: This is expected behavior - device mapper entries are persistent
- **Solution**: Manual cleanup using this tool is required; rebooting will NOT clear orphaned entries
- **Explanation**: The device mapper subsystem recreates entries from persistent LVM metadata during system startup
- **Note**: v8.2.2+ makes this worse by creating entries for ALL LVM volumes at boot

#### VM Creation Fails with "Device Busy" Error
- **Cause**: Proxmox automatically assigns the lowest available VM ID. If orphaned entries exist for that ID, creation fails
- **Example**: After deleting VM 119, Proxmox will try to assign ID 119 to the next new VM, but orphaned entries block this
- **Solution**: Run this tool to identify and remove orphaned entries before creating new VMs
- **Prevention**: Always clean orphaned entries after VM deletions to avoid future conflicts
- **Diagnostic**: Use `dmsetup table | grep <VMID>` to find conflicting entries

#### Devices Show as "IN USE" During Cleanup (NEW)
- **Cause**: VM is running or device has open file handles
- **Solution**: 
  1. Identify which VM uses the device
  2. Stop the VM gracefully
  3. Re-run the cleanup tool
  4. If device remains open, check for stuck processes with `lsof /dev/mapper/<device>`
- **Note**: This is a safety feature, not an error

## Security Considerations

### Access Control
- Script requires root privileges
- Limit access to authorized administrators
- Audit script execution through system logs

### Data Protection
- No VM data is modified or accessed
- Only device mapper metadata is affected
- Email reports may contain infrastructure details
- **Device open checks prevent accidental data loss** (NEW)

## Support and Maintenance

### System Requirements
- Proxmox VE 6.x or higher
- Root access to Proxmox nodes
- Standard Linux utilities (dmsetup, qm, awk, sed)
- Optional: Python 3.x for enhanced email encoding
- Optional but recommended: lsof and fuser for device open detection

### External Dependencies
- Mailjet API for email delivery (optional)
- Network connectivity for email reports
- No additional software installation required

## Appendix: Technical Reference

### Device Mapper Entry Format
```
<storage>-vm--<vmid>--disk--<number>

Examples:
- pve-vm--104--disk--1 (default storage)
- ssd--ha01-vm--119--disk--0 (custom storage with dash in name)
- vg--cluster01--storage01-vm--199--disk--1 (complex storage name)
```

**Note**: Single dashes in storage names become double dashes in device mapper

### Configuration File Locations
- VM Configurations: `/etc/pve/qemu-server/<vmid>.conf`
- Storage Configuration: `/etc/pve/storage.cfg`

### Key Commands Used
- `dmsetup ls` - List device mapper entries
- `dmsetup info <entry>` - Get device information including open count
- `dmsetup remove <entry>` - Remove device mapper entry
- `qm list` - List all VMs on node
- `pct list` - List all containers on node
- `lsof /dev/mapper/<entry>` - Check for open file handles (NEW in v36)
- `fuser /dev/mapper/<entry>` - Quick device usage check (NEW in v36)

### Device Open Status Detection (NEW in v36)

The tool uses a hierarchical approach to detect device usage:

1. **Primary Detection**: `dmsetup info` open count
   - Most reliable for device mapper entries
   - Shows exact number of open references

2. **Secondary Detection**: `lsof` file handle check
   - Identifies specific processes using the device
   - Provides detailed usage information

3. **Tertiary Detection**: `fuser` quick check
   - Fast boolean check for device usage
   - Fallback when lsof unavailable

---

**Document Version**: 1.1  
**Last Updated**: November 2024  
**Latest Version**: 36 (Device Open Safety)  
**Classification**: Internal Use Only