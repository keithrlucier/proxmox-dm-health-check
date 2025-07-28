# Documentation: Proxmox Device Mapper Issue Detector (Version 33)

## Overview

The **Proxmox Device Mapper Issue Detector v33** is a comprehensive Bash-based tool designed to detect and resolve critical device mapper issues that cause VM failures in Proxmox Virtual Environment (PVE). The script's primary focus is identifying **duplicate device mapper entries** - the most critical issue that causes unpredictable VM behavior and startup failures.

**Key Focus Areas:**
- **DUPLICATE ENTRIES** (Critical): Multiple device mapper entries for the same VM disk **on the same storage pool**
- **TOMBSTONED ENTRIES** (Warning): Orphaned entries for deleted VMs/disks that block future disk creation

The script performs real-time analysis, generates professional HTML reports with VM-specific health status, and delivers these reports via Mailjet email API. It includes a priority-based interactive cleanup mode for safe removal of problematic entries.

## Critical Fixes in v32/v33

### Version 32: Fixed False Positive Duplicates
**The Bug**: Script incorrectly identified different disks with the same number on different storage pools as duplicates.

**Example of the bug**:
- VM 119 has disk-0 on SSD-HA07 (EFI disk)
- VM 119 has disk-0 on SSD-HA01 (data disk)
- v31 would incorrectly flag these as duplicates!

**The Fix**: Duplicate detection now includes storage pool in the comparison (VM:STORAGE:DISK instead of just VM:DISK)

### Version 33: Fixed Storage Pool Extraction
**The Bug**: The regex failed to extract storage pool names, showing empty storage in duplicate detection.

**Example of the bug**:
```
❌ CRITICAL DUPLICATE: VM 119 storage  disk-0 has 2 device mapper entries!
```
Note the double space after "storage" - the pool name was missing.

**The Fix**: Corrected the storage pool extraction regex to properly parse device mapper names.

## Quick Start

```bash
# Download and run the script
wget https://raw.githubusercontent.com/keithrlucier/proxmox-dm-health-check/main/Proxmox_DM_Cleanup_v33.sh
chmod +x Proxmox_DM_Cleanup_v33.sh
./Proxmox_DM_Cleanup_v33.sh
```

The script will:
1. Analyze all device mapper entries
2. Detect true duplicates (same VM, storage, and disk)
3. Detect tombstones (orphaned entries)
4. Show VM health status
5. Send an email report (if configured)
6. Optionally offer interactive cleanup

## Key Features

### Core Detection Features
- **Duplicate Detection** (Priority 1): Identifies multiple DM entries for the same VM disk **on the same storage pool**
- **Tombstone Detection** (Priority 2): Finds orphaned DM entries that don't match any VM configuration
- **VM-Centric Analysis**: Shows health status for each VM on the node
- **Single-Pass Analysis**: No double-counting - each entry evaluated once
- **Accurate Storage Pool Parsing**: Correctly handles all storage naming formats

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
- GitHub Integration: Email footer includes repository and documentation links

### Interactive Cleanup
- Priority-based cleanup: Duplicates first, then tombstones
- Detailed explanations for each issue type
- Safe removal process with user confirmation
- Option to auto-remove all remaining entries

## Critical Issues Explained

### 🚨 Duplicate Device Mapper Entries (CRITICAL)

**What are they?**
Multiple device mapper entries pointing to the same VM disk **on the same storage pool**.

**What are NOT duplicates?**
- Same disk number on different storage pools (e.g., disk-0 on SSD-HA01 and disk-0 on SSD-HA07)
- These are legitimate configurations (e.g., EFI disk on one pool, data disk on another)

**True duplicate example:**
```
VM 169 config shows: scsi0: ssd-ha01:vm-169-disk-0
Device mapper has:
  - ssd--ha01-vm--169--disk--0  ✓ (correct)
  - ssd--ha01-vm--169--disk--0  ❌ (duplicate on SAME storage!)
```

**NOT a duplicate example (v33 handles correctly):**
```
VM 119 config shows:
  efidisk0: SSD-HA07:vm-119-disk-0
  scsi1: SSD-HA01:vm-119-disk-0
Device mapper has:
  - ssd--ha07-vm--119--disk--0  ✓ (EFI disk)
  - ssd--ha01-vm--119--disk--0  ✓ (Data disk - different storage!)
```

**Why are duplicates critical?**
- Cause unpredictable VM behavior
- Can lead to data corruption
- Result in "Device or resource busy" errors
- Make VM operations unreliable

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
- **Correctly extracts**: VM ID, storage pool, and disk number
- Single-pass classification into:
  - **Valid**: Matches VM configuration exactly
  - **Duplicate**: Multiple entries for same VM+storage+disk combination
  - **Tombstoned**: No matching VM or disk in config

### 3. **Duplicate Detection Algorithm (v33 improved)**
- Groups DM entries by **VM ID + Storage Pool + Disk Number**
- Only identifies TRUE duplicates (same storage pool)
- Correctly handles VMs with same disk numbers on different storage pools
- Provides clear visual grouping in output

### 4. **Storage Pool Extraction (v33 fixed)**
The script now correctly extracts storage pool names from device mapper entries:
- `ssd--ha01-vm--119--disk--0` → extracts `ssd-ha01`
- `t1--ha05-vm--183--disk--0` → extracts `t1-ha05`
- `t1b--ha04-vm--139--disk--0` → extracts `t1b-ha04`

### 5. **VM Health Status Table**
Shows for each VM on the node:
- **VM ID**: Numeric identifier
- **Name**: VM's descriptive name
- **Status**: 🟢 Running or ⚪ Stopped
- **DM Health**: 
  - ✅ Clean
  - 🚨 X storage:disk(s) DUPLICATED!
  - ⚠️ X tombstone(s)

### 6. **Health Grading System**
- **A+**: No issues found
- **B**: 1-5 tombstones only
- **C**: 6-20 tombstones only
- **D**: 21-50 tombstones only
- **F**: ANY duplicates OR 50+ tombstones

> **Note:** Duplicates automatically result in F grade due to their critical nature

### 7. **HTML Email Report**
Key sections include:
- Overall health status with grade
- Critical issues alert (duplicates highlighted)
- Device mapper analysis summary
- VM status table
- System information
- Action required section with cleanup instructions
- GitHub repository links in footer for documentation and support

### 8. **Priority-Based Interactive Cleanup**
Two-phase cleanup process:
1. **Priority 1 - Duplicates** (if any exist)
   - Shows storage pool for clarity
   - Keeps first entry, removes duplicates
   - Strong warnings about impact
2. **Priority 2 - Tombstones** (if any exist)
   - Removes orphaned entries
   - Prevents future conflicts

## Installation

### Option 1: Download from GitHub (Recommended)
```bash
# Download the latest version directly from GitHub
wget https://raw.githubusercontent.com/keithrlucier/proxmox-dm-health-check/main/Proxmox_DM_Cleanup_v33.sh -O /root/Proxmox_DM_Cleanup_v33.sh

# Set execution permissions
chmod +x /root/Proxmox_DM_Cleanup_v33.sh

# Run the script
./Proxmox_DM_Cleanup_v33.sh
```

### Option 2: Manual Installation
```bash
# Copy the script to the node
scp Proxmox_DM_Cleanup_v33.sh root@<node-ip>:/root/

# Set execution permissions
chmod +x /root/Proxmox_DM_Cleanup_v33.sh

# Run the script
./Proxmox_DM_Cleanup_v33.sh
```

## Usage Examples

### Basic Analysis (Read-Only)
```bash
./Proxmox_DM_Cleanup_v33.sh
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
119      Windows Server 2019            🟢 Running   ✅ Clean
169      Ubuntu 22.04                   ⚪ Stopped   🚨 1 storage:disk(s) DUPLICATED!
170      CentOS 8                       🟢 Running   ⚠️ 2 tombstone(s)
```

#### Duplicate Detection Output (v33 improved)
```
❌ CRITICAL DUPLICATE: VM 169 storage ssd-ha01 disk-0 has 2 device mapper entries!
   → This WILL cause unpredictable behavior and VM failures!
      - ssd--ha01-vm--169--disk--0
      - ssd--ha01-vm--169--disk--0
```

Note: Now shows the storage pool name for clarity!

## Scheduling with Cron

To run automated checks daily at 10 PM:

```bash
crontab -e
```

Add this line:
```bash
0 22 * * * /root/Proxmox_DM_Cleanup_v33.sh > /var/log/proxmox_dm_check.log 2>&1
```

## Configuration

### Script Variables

Edit these variables at the top of the script:

```bash
MAILJET_API_KEY="your-api-key"
MAILJET_API_SECRET="your-api-secret"
FROM_EMAIL="automation@yourdomain.com"
FROM_NAME="ProxMox DM Issue Detector"
TO_EMAIL="admin@yourdomain.com"
```

### Mailjet Email Service Setup

[Mailjet](https://www.mailjet.com) is the email delivery service used for sending HTML reports.

#### Setting up Mailjet:

1. **Create Account**: Sign up at [https://app.mailjet.com/signup](https://app.mailjet.com/signup)

2. **Get API Credentials**:
   - Navigate to Account Settings → API Keys
   - Click "Create API Key"
   - Save both API Key and Secret Key

3. **Verify Sender**:
   - Go to Senders & Domains
   - Add your FROM_EMAIL address
   - Confirm the verification email

4. **Optional**: Configure domain authentication for better deliverability

## Safety and Best Practices

### ✅ Safe by Design
- **Read-Only by Default**: No changes without explicit user consent
- **Accurate Detection**: Only flags TRUE duplicates (same storage pool)
- **Priority-Based**: Critical issues (duplicates) handled first
- **Clear Explanations**: Each issue explained before action
- **No Data Loss**: Removes only device mapper entries, not actual disk data

### ⚠️ When to Run Cleanup
- **Immediately**: If duplicates are detected (critical issue)
- **Soon**: If many tombstones exist (blocks VM operations)
- **Maintenance Window**: For large-scale cleanup operations

### 🚨 What Gets Removed
- **Duplicates**: Extra device mapper entries on the SAME storage pool
- **Tombstones**: Orphaned entries with no VM configuration
- **NOT Removed**: 
  - Different disks with same number on different storage pools
  - Actual disk data
  - VM configurations
  - Storage content

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

### Scenario 5: Multiple Disks on Different Storage
**Symptoms**: VM has disk-0 on multiple storage pools (legitimate config)
**v33 Behavior**: Correctly identifies these as separate, valid disks
**No Action Needed**: These are NOT duplicates

## Testing the Script

### Create Test Scenarios

#### Test True Duplicate Detection
```bash
# Create a TRUE duplicate entry (same storage pool)
dmsetup create test--ha01-vm--999--disk--0 --table '0 204800 linear /dev/sda 0'
dmsetup create test--ha01-vm--999--disk--0-dup --table '0 204800 linear /dev/sda 0'
```

#### Test Different Storage Pools (NOT duplicates)
```bash
# Create entries on different storage pools (should NOT be flagged as duplicates)
dmsetup create ssd--ha01-vm--998--disk--0 --table '0 204800 linear /dev/sda 0'
dmsetup create ssd--ha07-vm--998--disk--0 --table '0 204800 linear /dev/sdb 0'
```

#### Test Tombstone Detection
```bash
# Create an orphaned entry
dmsetup create test--ha01-vm--888--disk--0 --table '0 204800 linear /dev/sda 0'
```

### Cleanup Test Entries
```bash
dmsetup remove test--ha01-vm--999--disk--0
dmsetup remove test--ha01-vm--999--disk--0-dup
dmsetup remove ssd--ha01-vm--998--disk--0
dmsetup remove ssd--ha07-vm--998--disk--0
dmsetup remove test--ha01-vm--888--disk--0
```

## Version History

### 🆕 Version 33 (Current)
- **CRITICAL FIX**: Storage pool extraction regex corrected
- **Fixed Bug**: Empty storage pool names in duplicate detection
- **Improvement**: Now shows storage pool in duplicate detection output

### 📋 Version 32
- **CRITICAL FIX**: Duplicate detection includes storage pool
- **Fixed Bug**: False positives for same disk number on different storage pools
- **Improvement**: Correctly handles complex VM disk configurations

### 📋 Version 31
- **New Feature**: GitHub integration in email reports
- **Enhancement**: Repository links in email footer
- **Improvement**: Easy access to documentation and issue reporting

### 🎯 Core Features (from v30)
- **Primary Focus**: Duplicate detection (critical VM-breaking issue)
- **Secondary Focus**: Tombstone detection (blocks operations)
- **VM Status Dashboard**: Shows health for each VM on node
- **Single-Pass Analysis**: Accurate counting without duplication
- **Priority Cleanup**: Handles critical issues first

## Dependencies

### Required Tools
- **Proxmox Tools**: `qm`, `pct`, `dmsetup`
- **Core Linux**: `awk`, `sed`, `grep`, `sort`, `uniq`, `wc`
- **Email Delivery**: `curl` (for Mailjet API)
- **System Info**: `top`, `free`, `df`, `uptime`, `lscpu`

### Optional Tools
- `dmidecode` - System hardware information
- `ip` - Network interface details
- Additional monitoring tools

All required tools are typically pre-installed on Proxmox nodes.

## GitHub Repository

The Proxmox Device Mapper Issue Detector is open source and available on GitHub:

**Repository**: [https://github.com/keithrlucier/proxmox-dm-health-check](https://github.com/keithrlucier/proxmox-dm-health-check)

### Available Resources:
- **Source Code**: Latest version of the script
- **Documentation**: This document and additional guides
- **Issue Tracker**: Report bugs or request features
- **Releases**: Version history and changelogs

### Contributing
- Fork the repository
- Create feature branches
- Submit pull requests
- Report issues with detailed information

## Support

### Getting Help
- **GitHub Issues**: [Report problems or request features](https://github.com/keithrlucier/proxmox-dm-health-check/issues)
- **Documentation**: [Full documentation online](https://github.com/keithrlucier/proxmox-dm-health-check/blob/main/Documentation.md)
- **Author**: Keith R. Lucier - keithrlucier@gmail.com
- **Company**: ProSource Technology Solutions - [www.getprosource.com](https://www.getprosource.com)

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

### False Positive Duplicates (Fixed in v32/v33)
- **v31 Bug**: Would flag different storage pools as duplicates
- **Solution**: Upgrade to v33 which correctly handles multiple storage pools

### Empty Storage Pool Names (Fixed in v33)
- **v32 Bug**: Storage pool extraction regex failed
- **Solution**: v33 includes corrected regex for all storage naming formats

## Summary

The Proxmox Device Mapper Issue Detector v33 fills a critical gap in Proxmox operations by identifying and resolving device mapper issues that cause VM failures. By correctly detecting only TRUE duplicates (same VM, storage pool, and disk), the script helps administrators maintain stable and predictable VM operations without false alarms.

**Critical Fixes in v32/v33**:
- **v32**: Fixed false positive duplicate detection for VMs with disks on multiple storage pools
- **v33**: Fixed storage pool extraction to correctly parse all naming formats

The tool is essential for:
- Clusters with frequent VM migrations
- Environments with high VM churn
- Complex VM configurations with multiple storage pools
- Recovery from failed operations
- Preventive maintenance
- Troubleshooting VM startup issues

Regular use of this script (via cron) provides early warning of developing issues and maintains a clean, efficient Proxmox environment. The accurate detection ensures administrators focus on real problems without wasting time on false positives.

**Remember**: 
- TRUE duplicates (same storage pool) are critical and require immediate attention
- Different storage pools with same disk number are NORMAL and valid
- Tombstones are important but less urgent
- The script's priority-based approach ensures the most dangerous issues are addressed first

## License

This project is licensed under the MIT License. See the [LICENSE](https://github.com/keithrlucier/proxmox-dm-health-check/blob/main/LICENSE) file for details.

---
**End of Documentation v33**