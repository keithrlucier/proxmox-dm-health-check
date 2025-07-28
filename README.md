# 🚨 Proxmox Device Mapper Issue Detector & Cleanup Toolkit

**Author**: Keith R. Lucier — keithrlucier@gmail.com  
**Version**: 35  
**Purpose**: Detect and fix **TRUE DUPLICATE** device mapper entries that cause VM failures

---

## ⚠️ IMPORTANT DISCLAIMER - USE AT YOUR OWN RISK

**This script directly modifies device mapper entries which are critical to VM operations. While designed with safety features and confirmation prompts, YOU USE THIS SCRIPT ENTIRELY AT YOUR OWN RISK.**

- **NO WARRANTY**: Provided "AS IS" without warranty of any kind
- **NO SUPPORT**: No support is offered or implied
- **YOUR RESPONSIBILITY**: You bear full responsibility for any outcomes
- **BACKUP FIRST**: Always ensure proper backups before running cleanup
- **TEST FIRST**: Test in non-production environments before production use

---

## 🎯 Critical Issue Focus

This toolkit primarily targets **DUPLICATE DEVICE MAPPER ENTRIES** - the #1 cause of VM failures in Proxmox environments. When multiple device mapper entries exist for the same VM disk **on the same storage pool**, it causes:

- ❌ **Unpredictable VM behavior**
- ❌ **"Device or resource busy" errors**  
- ❌ **VM startup failures**
- ❌ **Potential data corruption**

**Version 35 accurately detects ONLY TRUE duplicates and tombstones** - with proper storage pool verification and case-insensitive comparison to eliminate false positives.

---

## 🚀 Overview

The Proxmox Device Mapper Issue Detector is a professionally engineered Bash script that identifies and resolves device mapper problems that cause VM failures. It performs comprehensive analysis, provides VM-specific health status, and offers safe interactive cleanup of problematic entries.

**Key Focus Areas:**
- 🚨 **TRUE DUPLICATE ENTRIES** (Critical): Multiple DM entries for same VM disk on same storage
- ⚠️ **TOMBSTONED ENTRIES** (Warning): Orphaned entries that block disk creation
- ✅ **ACCURATE DETECTION** (v35): No false positives - handles case differences correctly

**🆕 Critical Fixes in v32/v33/v34/v35:**
- **v32**: Fixed false positive duplicates for different storage pools
- **v33**: Fixed storage pool extraction for accurate detection
- **v34**: Fixed false positive tombstones + added nvme/mpath support
- **v35**: Fixed case sensitivity bug for uppercase storage pools

---

## 🔍 What It Does

### Primary Detection & Analysis
- 🚨 **Detects TRUE DUPLICATE device mapper entries** (same VM, storage, and disk)
- ✅ **Correctly handles multi-storage VMs** (e.g., EFI on one pool, data on another)
- ⚠️ **Identifies TRUE tombstoned entries** (with storage pool verification)
- 🎯 **Case-insensitive comparison** (v35) - handles T1-HA07 vs t1--ha07 correctly
- 📊 **VM health dashboard** showing status for each VM on the node
- ✅ **Single-pass analysis** with accurate issue counting
- 📧 **Professional HTML reports** with color-coded severity levels
- 🔧 **Priority-based cleanup** (duplicates first, then tombstones)

### VM Status Dashboard
Shows for every VM on the node:
- **VM ID & Name**
- **Running Status** (🟢 Running / ⚪ Stopped)
- **DM Health**:
  - ✅ Clean
  - 🚨 X storage:disk(s) DUPLICATED!
  - ⚠️ X tombstone(s)

### System Health Grading
- **A+**: Perfect health (no issues)
- **B-D**: Tombstones only (varying severity)
- **F**: ANY duplicates detected (critical failure)

---

## ✨ Key Features

### Accurate Issue Detection (v35 Perfected)
- 🚨 **True Duplicate Detection** - Finds multiple DM entries for same VM+storage+disk
- ✅ **Multi-Storage Support** - Correctly handles VMs with disks on different storage pools
- ⚠️ **True Tombstone Detection** - Identifies orphaned entries with storage pool verification
- 🎯 **Case-Insensitive Matching** - No false positives from uppercase storage names
- 📊 **VM-Centric Analysis** - Shows health status per VM
- 🎯 **Zero False Positives** - No incorrect flagging of legitimate configurations
- 🆕 **Extended Disk Support** - Now recognizes nvme and mpath disk types

### Reporting & Monitoring
- 📧 **HTML Email Reports** via Mailjet API
- 🎨 **Color-Coded Severity** (Red=Critical, Yellow=Warning, Green=Good)
- 📈 **Performance Metrics** (CPU, RAM, uptime, storage)
- 🏆 **Health Grade** (A+ to F based on issue severity)
- 🔗 **GitHub Links** for documentation and issue tracking

### Safe Interactive Cleanup
- 🔒 **Read-only by default** - No changes without consent
- 📝 **Detailed explanations** for each issue before removal
- 🎯 **Priority handling** - Critical duplicates cleaned first
- ✅ **User confirmation** required for each action

---

## 🎯 Understanding Critical Issues

### 🚨 TRUE Duplicate Device Mapper Entries (CRITICAL)

**TRUE Duplicate Example:**
```
VM 169 config shows: scsi0: ssd-ha01:vm-169-disk-0

Device mapper has:
  ssd--ha01-vm--169--disk--0  ✓ (correct)
  ssd--ha01-vm--169--disk--0  ❌ (DUPLICATE on same storage!)
```

**NOT a Duplicate (v35 handles correctly):**
```
VM 119 config shows: 
  efidisk0: SSD-HA07:vm-119-disk-0  (EFI disk)
  scsi1: SSD-HA01:vm-119-disk-0     (Data disk)

Device mapper has:
  ssd--ha07-vm--119--disk--0  ✅ (EFI on HA07 - VALID)
  ssd--ha01-vm--119--disk--0  ✅ (Data on HA01 - VALID)
```

**Impact of TRUE Duplicates:**
- Causes unpredictable VM behavior
- Results in "Device busy" errors
- Can corrupt VM operations
- **Requires immediate cleanup**

### ⚠️ TRUE Tombstoned Entries (WARNING)

**TRUE Tombstone Example (v35):**
```
Device mapper has: ssd--ha01-vm--119--disk--0
VM 119 config shows NO disk-0 on storage ssd-ha01 (or SSD-HA01)
Result: ❌ TOMBSTONE (correctly identified)
```

**NOT a Tombstone (v35 fixes case sensitivity):**
```
Config shows: T1-HA07:vm-115-disk-0 (uppercase)
Device mapper has: t1--ha07-vm--115--disk--0 (lowercase)
Result: ✅ VALID (v35 correctly matches despite case difference)
```

**Impact:**
- Blocks creation of new VMs with that ID
- Prevents disk creation with conflicting names
- Wastes system resources
- **Should be cleaned during maintenance**

---

## 📁 Installation

### Option 1: Download from GitHub
```bash
# Download latest version
wget https://raw.githubusercontent.com/keithrlucier/proxmox-dm-health-check/main/Proxmox_DM_Cleanup_v35.sh

# Make executable
chmod +x Proxmox_DM_Cleanup_v35.sh

# Run analysis
./Proxmox_DM_Cleanup_v35.sh
```

### Option 2: Manual Creation
```bash
# Create/edit the script
nano /root/Proxmox_DM_Cleanup_v35.sh

# Make executable
chmod +x /root/Proxmox_DM_Cleanup_v35.sh

# Run analysis
./Proxmox_DM_Cleanup_v35.sh
```

---

## 🕒 Schedule Daily Checks (10 PM)

```bash
crontab -e
```

Add this line:
```bash
0 22 * * * /root/Proxmox_DM_Cleanup_v35.sh > /var/log/proxmox_dm_check.log 2>&1
```

---

## 📊 Sample Output (v35 Accurate Detection)

### VM Status Section (v35 - no false positives)
```
🖥️  VM STATUS ON THIS NODE
=========================================

VM ID    NAME                           STATUS       DM HEALTH
-----    ----                           ------       ---------
115      Windows Server 2019            🟢 Running   ✅ Clean
119      Multi-Storage VM               🟢 Running   ✅ Clean
125      Ubuntu 22.04 LTS               ⚪ Stopped   ✅ Clean
138      Development Server             ⚪ Stopped   ✅ Clean
145      Database Server                🟢 Running   ✅ Clean
191      Web Server                     ⚪ Stopped   ✅ Clean

Additionally, tombstones exist for 29 non-existent VM IDs:
   VM 198   : 2 tombstone(s) ❌ VM DOES NOT EXIST
   VM 188   : 2 tombstone(s) ❌ VM DOES NOT EXIST
```

### Critical Issue Detection (v35 with case-insensitive matching)
```
🔍 ANALYZING DEVICE MAPPER ISSUES
=========================================

Step 3: Detecting DUPLICATE entries (critical issue!)...

✅ No duplicate entries found

Step 4: Identifying tombstoned entries...

❌ TOMBSTONE: t1--ha01-vm--103--disk--0
   → VM 103 does not exist on this node
   → This will block VM 103 from creating disk-0 on storage t1-ha01!

📊 ANALYSIS SUMMARY
=========================================
   Total device mapper entries: 62
   Valid entries: 4 ✅ (v35 correctly identifies valid entries)
   Duplicate entries: 0 ✅
   Tombstoned entries: 58 ⚠️ WILL BLOCK DISK CREATION!
   Total issues: 58
```

### Before v35 (Case Sensitivity Bug)
```
   Valid entries: 0 ❌ (v34 bug - all marked as tombstones!)
   Tombstoned entries: 62 ❌ (false positives from case mismatch)
```

---

## 🔒 Safety Features

### What Gets Cleaned
- ✅ **TRUE Duplicate DM entries** (same storage pool, keeps first, removes extras)
- ✅ **TRUE Tombstoned entries** (orphaned with proper storage pool verification)

### What's Protected
- ✅ **Multi-storage configurations** - Different pools with same disk number are VALID
- ✅ **Case differences** - T1-HA07 matches t1--ha07 correctly (v35)
- ✅ **VM disk data** - Never touched
- ✅ **VM configurations** - Read-only access
- ✅ **Active VMs** - Never modified
- ✅ **Storage backends** - Unaffected

### Cleanup Priority
1. **TRUE DUPLICATES FIRST** - Critical issues that break VMs
2. **Tombstones second** - Important but less urgent

---

## 📬 Email Configuration

Configure Mailjet API credentials in the script:

```bash
MAILJET_API_KEY="your-api-key"
MAILJET_API_SECRET="your-api-secret"
FROM_EMAIL="automation@yourdomain.com"
FROM_NAME="ProxMox DM Issue Detector"
TO_EMAIL="admin@yourdomain.com"
```

### Email Report Features
- **Subject indicates severity**: 
  - 🚨 CRITICAL: TRUE duplicates found
  - ⚠️ WARNING: Tombstones only
  - ✅ EXCELLENT: No issues
- **Storage pool shown** in all detections
- **Color-coded health status**
- **VM-specific issue breakdown**
- **Clear action items**
- **GitHub repository links** for documentation

---

## 🧪 Testing the Script

### Create Test TRUE Duplicate (Use Carefully!)
```bash
# Create TRUE duplicate entries (same storage) for testing
dmsetup create ssd--ha01-vm--999--disk--0 --table '0 204800 linear /dev/sda 0'
dmsetup create ssd--ha01-vm--999--disk--0-dup --table '0 204800 linear /dev/sda 0'
```

### Create Test Multi-Storage (NOT duplicates)
```bash
# Create entries on different storage pools (should NOT be flagged)
dmsetup create ssd--ha01-vm--998--disk--0 --table '0 204800 linear /dev/sda 0'
dmsetup create ssd--ha07-vm--998--disk--0 --table '0 204800 linear /dev/sdb 0'
```

### Create Test Tombstone
```bash
# Create orphaned entry
dmsetup create test--ha01-vm--888--disk--0 --table '0 204800 linear /dev/sda 0'
```

### Cleanup Test Entries
```bash
dmsetup remove ssd--ha01-vm--999--disk--0
dmsetup remove ssd--ha01-vm--999--disk--0-dup
dmsetup remove ssd--ha01-vm--998--disk--0
dmsetup remove ssd--ha07-vm--998--disk--0
dmsetup remove test--ha01-vm--888--disk--0
```

---

## 🆕 Version History

### Version 35 (Current) - Case Insensitive Fix
- 🔧 **CRITICAL FIX**: Storage pools now compared case-insensitively
- 🚨 **FIXED**: False positive tombstones when storage uses uppercase (T1-HA07 vs t1--ha07)
- 📊 **IMPACT**: Anyone using uppercase storage pool names now gets accurate results
- ✅ **RESULT**: Zero false positives - all valid entries correctly identified

### Version 34 - Storage Pool Verification
- 🔧 **CRITICAL FIX**: Tombstone detection now includes storage pool verification
- 🚨 **FIXED**: False positive tombstones for multi-storage configurations
- 🆕 **NEW**: Added support for nvme and mpath disk prefixes
- 📊 **IMPROVED**: Better storage pool name extraction preserving legitimate "--"
- 🔒 **ENHANCED**: Python-based JSON escaping for more reliable emails

### Version 33 - Storage Pool Fix
- 🔧 **FIXED**: Storage pool extraction regex now works correctly
- 🎯 **FIXED**: Empty storage names in duplicate detection output
- 📊 **IMPROVED**: Shows storage pool name in duplicate detection

### Version 32 - Major Bug Fix
- 🚨 **FIXED**: False positive duplicates for different storage pools
- ✅ **NEW**: Duplicate detection includes storage pool (VM:STORAGE:DISK)
- 🎯 **IMPROVED**: Correctly handles VMs with disks on multiple storage pools

### Version 31 - GitHub Integration
- 🔗 **GitHub Integration** - Added repository links to email reports
- 📄 **Easy Access** - Direct links to documentation from email footer
- 🐛 **Bug Tracking** - Users can report issues directly from email

### Version 30 - Major Refactor
- 🎯 **Focus on DUPLICATES** as the critical issue
- 📊 **VM Status Dashboard** showing health per VM
- 🔢 **Accurate counting** - no more double-counting
- 🏷️ **Simplified terminology** - Valid, Duplicate, or Tombstoned only
- 🎨 **Visual health indicators** (🚨, ⚠️, ✅)
- 📧 **Enhanced email subjects** clearly indicate severity

---

## 🛠 Dependencies

- Proxmox tools: `qm`, `pct`, `dmsetup`
- Linux tools: `awk`, `sed`, `grep`, `sort`, `uniq`, `tr`
- Email: `curl`, Mailjet API
- Optional: `python3` (for enhanced email escaping), `top`, `free`, `df`, `uptime`

---

## 🚨 Common Issues & Solutions

### VM Won't Start - "Device Busy"
**Cause**: TRUE duplicate or tombstoned entries  
**Fix**: Run script, clean issues for that VM

### Can't Create VM with Specific ID
**Cause**: Tombstoned entries from old VM  
**Fix**: Run script, remove tombstones

### VM Behaving Unpredictably
**Cause**: TRUE DUPLICATE entries (critical!)  
**Fix**: Run script IMMEDIATELY

### After Failed Migration
**Symptom**: Leftover entries on source  
**Fix**: Run script on source node

### False Positive Duplicates (FIXED in v32/v33)
**Old Bug**: v31 flagged different storage pools as duplicates  
**v35 Behavior**: Correctly identifies only TRUE duplicates

### False Positive Tombstones - Multi-Pool (FIXED in v34)
**Old Bug**: v33 flagged multi-storage configs as tombstones  
**v35 Behavior**: Properly verifies storage pool in tombstone detection

### False Positive Tombstones - Case Sensitivity (FIXED in v35)
**Old Bug**: v34 flagged uppercase storage pools as tombstones  
**Example**: T1-HA07 (config) vs t1--ha07 (DM) = false tombstone  
**v35 Behavior**: Case-insensitive comparison eliminates false positives

---

## 👨‍💻 Author

**Keith R. Lucier**  
✉️ keithrlucier@gmail.com  
🔗 [LinkedIn Profile](https://www.linkedin.com/in/keithrlucier/)  

Created this tool to solve critical Proxmox device mapper issues that were causing VM failures in production environments. The script represents extensive real-world testing and refinement to ensure accurate detection without false positives.

**Remember**: This tool is provided AS-IS with no warranty or support. Use at your own risk.

---

## 💬 Community Resources

- **GitHub Repository**: [Source code and documentation](https://github.com/keithrlucier/proxmox-dm-health-check)
- **Issue Tracker**: [Report bugs or share experiences](https://github.com/keithrlucier/proxmox-dm-health-check/issues)
- **Documentation**: [Full documentation](https://github.com/keithrlucier/proxmox-dm-health-check/blob/main/Documentation.md)

**Note**: No support is offered. Issues may be reviewed but responses are not guaranteed.

---

## ⚠️ Final Warning

**USE AT YOUR OWN RISK**. This script modifies critical system components. While it includes safety features and requires confirmation for changes, you are solely responsible for:

- Understanding your environment
- Having proper backups
- Testing in non-production first
- Any outcomes from using this tool

The author assumes no liability for any issues, data loss, or system problems that may result from using this script.

---

## 📄 License

MIT License - See the [LICENSE](https://github.com/keithrlucier/proxmox-dm-health-check/blob/main/LICENSE) file for details.

---

**Keywords**: Proxmox duplicate device mapper, VM startup failures, device busy errors, tombstoned entries, VM disk conflicts, Proxmox storage cleanup, device mapper troubleshooting, VM health monitoring, multi-storage VM support, false positive duplicates fixed, false positive tombstones fixed, nvme mpath support, case insensitive storage pools

---

## 🔗 Quick Links

- [GitHub Repository](https://github.com/keithrlucier/proxmox-dm-health-check)
- [Full Documentation](https://github.com/keithrlucier/proxmox-dm-health-check/blob/main/Documentation.md)
- [Issue Tracker](https://github.com/keithrlucier/proxmox-dm-health-check/issues)
- [Latest Release](https://github.com/keithrlucier/proxmox-dm-health-check/releases)

---

**Remember**: v35 provides accurate detection with ZERO false positives - handling case differences, multi-storage configurations, and modern disk types correctly! 🚨