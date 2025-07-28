# 🚨 Proxmox Device Mapper Issue Detector & Cleanup Toolkit

**Author**: Keith R Lucier — keithrlucier@gmail.com  
**ProSource** - www.getprosource.com  
**Version**: 33  
**Purpose**: Detect and fix **TRUE DUPLICATE** device mapper entries that cause VM failures

---

## 🎯 Critical Issue Focus

This toolkit primarily targets **DUPLICATE DEVICE MAPPER ENTRIES** - the #1 cause of VM failures in Proxmox environments. When multiple device mapper entries exist for the same VM disk **on the same storage pool**, it causes:

- ❌ **Unpredictable VM behavior**
- ❌ **"Device or resource busy" errors**  
- ❌ **VM startup failures**
- ❌ **Potential data corruption**

**Version 33 accurately detects ONLY TRUE duplicates** - multiple entries for the same VM, storage pool, and disk combination.

---

## 🚀 Overview

The Proxmox Device Mapper Issue Detector is a professionally engineered Bash script that identifies and resolves device mapper problems that cause VM failures. It performs comprehensive analysis, provides VM-specific health status, and offers safe interactive cleanup of problematic entries.

**Key Focus Areas:**
- 🚨 **TRUE DUPLICATE ENTRIES** (Critical): Multiple DM entries for same VM disk on same storage
- ⚠️ **TOMBSTONED ENTRIES** (Warning): Orphaned entries that block disk creation
- ✅ **ACCURATE DETECTION** (v33): No false positives for multi-storage configurations

**🆕 Critical Fixes in v32/v33:**
- **v32**: Fixed false positive duplicates for different storage pools
- **v33**: Fixed storage pool extraction for accurate detection

---

## 🔍 What It Does

### Primary Detection & Analysis
- 🚨 **Detects TRUE DUPLICATE device mapper entries** (same VM, storage, and disk)
- ✅ **Correctly handles multi-storage VMs** (e.g., EFI on one pool, data on another)
- ⚠️ **Identifies tombstoned entries** (orphaned DM entries with no VM config)
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

### Accurate Issue Detection (v33 Improved)
- 🚨 **True Duplicate Detection** - Finds multiple DM entries for same VM+storage+disk
- ✅ **Multi-Storage Support** - Correctly handles VMs with disks on different storage pools
- ⚠️ **Tombstone Detection** - Identifies orphaned entries from deleted VMs/disks
- 📊 **VM-Centric Analysis** - Shows health status per VM
- 🎯 **Zero False Positives** - No incorrect flagging of legitimate configurations

### Reporting & Monitoring
- 📧 **HTML Email Reports** via Mailjet API
- 🎨 **Color-Coded Severity** (Red=Critical, Yellow=Warning, Green=Good)
- 📈 **Performance Metrics** (CPU, RAM, uptime, storage)
- 🏆 **Health Grade** (A+ to F based on issue severity)
- 🔗 **GitHub Links** for documentation and support

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

**NOT a Duplicate (v33 handles correctly):**
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

### ⚠️ Tombstoned Entries (WARNING)

**Example Problem:**
```
Device mapper has: ssd--ha01-vm--999--disk--0
But VM 999 doesn't exist on this node!
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
wget https://raw.githubusercontent.com/keithrlucier/proxmox-dm-health-check/main/Proxmox_DM_Cleanup_v33.sh

# Make executable
chmod +x Proxmox_DM_Cleanup_v33.sh

# Run analysis
./Proxmox_DM_Cleanup_v33.sh
```

### Option 2: Manual Creation
```bash
# Create/edit the script
nano /root/Proxmox_DM_Cleanup_v33.sh

# Make executable
chmod +x /root/Proxmox_DM_Cleanup_v33.sh

# Run analysis
./Proxmox_DM_Cleanup_v33.sh
```

---

## 🕒 Schedule Daily Checks (10 PM)

```bash
crontab -e
```

Add this line:
```bash
0 22 * * * /root/Proxmox_DM_Cleanup_v33.sh > /var/log/proxmox_dm_check.log 2>&1
```

---

## 📊 Sample Output (v33 Accurate Detection)

### VM Status Section
```
🖥️  VM STATUS ON THIS NODE
=========================================

VM ID    NAME                           STATUS       DM HEALTH
-----    ----                           ------       ---------
115      Windows Server 2019            🟢 Running   🚨 1 storage:disk(s) DUPLICATED!
119      Multi-Storage VM               🟢 Running   ✅ Clean
125      Ubuntu 22.04 LTS               ⚪ Stopped   ✅ Clean
138      Development Server             ⚪ Stopped   ⚠️ 1 tombstone(s)
145      Database Server                🟢 Running   ✅ Clean
191      Web Server                     ⚪ Stopped   ✅ Clean

Additionally, tombstones exist for 69 non-existent VM IDs:
   VM 169    : 2 tombstone(s) ❌ VM DOES NOT EXIST
   VM 127    : 2 tombstone(s) ❌ VM DOES NOT EXIST
```

### Critical Issue Detection (v33 shows storage pool)
```
🔍 ANALYZING DEVICE MAPPER ISSUES
=========================================

Step 3: Detecting DUPLICATE entries (critical issue!)...

❌ CRITICAL DUPLICATE: VM 115 storage ssd-ha01 disk-0 has 2 device mapper entries!
   → This WILL cause unpredictable behavior and VM failures!
      - ssd--ha01-vm--115--disk--0
      - ssd--ha01-vm--115--disk--0

✅ No duplicate entries found

📊 ANALYSIS SUMMARY
=========================================
   Total device mapper entries: 177
   Valid entries: 175
   Duplicate entries: 2 🚨 CRITICAL ISSUE!
   Tombstoned entries: 0 ✅
   Total issues: 2
```

---

## 🔒 Safety Features

### What Gets Cleaned
- ✅ **TRUE Duplicate DM entries** (same storage pool, keeps first, removes extras)
- ✅ **Tombstoned entries** (orphaned with no VM config)

### What's Protected
- ✅ **Multi-storage configurations** - Different pools with same disk number are VALID
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
- **Storage pool shown** in duplicate detection
- **Color-coded health status**
- **VM-specific issue breakdown**
- **Clear action items**
- **GitHub repository links** for documentation and support

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
dmsetup create test--vm--888--disk--0 --table '0 204800 linear /dev/sda 0'
```

### Cleanup Test Entries
```bash
dmsetup remove ssd--ha01-vm--999--disk--0
dmsetup remove ssd--ha01-vm--999--disk--0-dup
dmsetup remove ssd--ha01-vm--998--disk--0
dmsetup remove ssd--ha07-vm--998--disk--0
dmsetup remove test--vm--888--disk--0
```

---

## 🆕 Version History

### Version 33 (Current) - Critical Fixes
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
- Linux tools: `awk`, `sed`, `grep`, `sort`, `uniq`
- Email: `curl`, Mailjet API
- Optional: `top`, `free`, `df`, `uptime`

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

### False Positives (FIXED in v32/v33)
**Old Bug**: v31 flagged different storage pools as duplicates  
**v33 Behavior**: Correctly identifies only TRUE duplicates

---

## 👨‍💻 Author & Support

**Keith R. Lucier**  
Senior Engineer & Systems Administrator | Microsoft Ecosystem Specialist | Power Platform Developer  
🔗 [LinkedIn Profile](https://www.linkedin.com/in/keithrlucier/)  
✉️ keithrlucier@gmail.com

**ProSource Technology Solutions**  
🌐 [www.getprosource.com](https://www.getprosource.com)

Providing frictionless, responsive, and secure business technology solutions, Keith is a seasoned IT professional with over 30 years of experience leading enterprise environments and delivering results at scale. He has served as a former IT Director for an organization with over 500 employees and currently specializes in:

- Microsoft 365 and Azure ecosystem administration
- Power Platform development and automation
- AI & hybrid cloud integrations
- Enterprise IT strategy and systems modernization
- **Proxmox virtualization and storage troubleshooting**
- **Device mapper issue resolution and VM recovery**
- **Multi-storage VM configuration management**
- Disaster recovery planning and implementation

Keith combines a deep understanding of business needs with expert-level systems knowledge to architect responsive and resilient infrastructures that prioritize uptime, security, and user empowerment.

### 💬 Getting Help

- **GitHub Issues**: [Report bugs or request features](https://github.com/keithrlucier/proxmox-dm-health-check/issues)
- **Documentation**: [Full documentation](https://github.com/keithrlucier/proxmox-dm-health-check/blob/main/Documentation.md)
- **Email**: keithrlucier@gmail.com

---

## ⚠️ Disclaimer

This script is provided as-is. While designed with safety in mind, always understand your environment before running cleanup operations. The script is read-only by default and requires explicit confirmation for any changes.

---

## 📄 License

MIT

---

**Keywords**: Proxmox duplicate device mapper, VM startup failures, device busy errors, tombstoned entries, VM disk conflicts, Proxmox storage cleanup, device mapper troubleshooting, VM health monitoring, multi-storage VM support, false positive duplicates fixed

---

## 🔗 Quick Links

- [GitHub Repository](https://github.com/keithrlucier/proxmox-dm-health-check)
- [Full Documentation](https://github.com/keithrlucier/proxmox-dm-health-check/blob/main/Documentation.md)
- [Issue Tracker](https://github.com/keithrlucier/proxmox-dm-health-check/issues)
- [Latest Release](https://github.com/keithrlucier/proxmox-dm-health-check/releases)

---

**Remember**: Only TRUE duplicates (same storage pool) are CRITICAL! Different storage pools are VALID! 🚨