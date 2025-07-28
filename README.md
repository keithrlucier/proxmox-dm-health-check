# 🚨 Proxmox Device Mapper Issue Detector & Cleanup Toolkit

**Author**: Keith R Lucier — keithrlucier@gmail.com  
**ProSource** - www.getprosource.com  
**Version**: 31  
**Purpose**: Detect and fix **DUPLICATE** device mapper entries that cause VM failures

---

## 🎯 Critical Issue Focus

This toolkit primarily targets **DUPLICATE DEVICE MAPPER ENTRIES** - the #1 cause of VM failures in Proxmox environments. When multiple device mapper entries exist for the same VM disk, it causes:

- ❌ **Unpredictable VM behavior**
- ❌ **"Device or resource busy" errors**  
- ❌ **VM startup failures**
- ❌ **Potential data corruption**

**Version 31 prioritizes duplicate detection** as these are CRITICAL issues that break VM operations.

---

## 🚀 Overview

The Proxmox Device Mapper Issue Detector is a professionally engineered Bash script that identifies and resolves device mapper problems that cause VM failures. It performs comprehensive analysis, provides VM-specific health status, and offers safe interactive cleanup of problematic entries.

**Key Focus Areas:**
- 🚨 **DUPLICATE ENTRIES** (Critical): Multiple DM entries for same VM disk
- ⚠️ **TOMBSTONED ENTRIES** (Warning): Orphaned entries that block disk creation

**🆕 New in v31:** Email reports now include direct GitHub links for easy access to documentation and issue reporting.

---

## 🔍 What It Does

### Primary Detection & Analysis
- 🚨 **Detects DUPLICATE device mapper entries** (critical VM-breaking issue)
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
  - 🚨 X disk(s) DUPLICATED!
  - ⚠️ X tombstone(s)

### System Health Grading
- **A+**: Perfect health (no issues)
- **B-D**: Tombstones only (varying severity)
- **F**: ANY duplicates detected (critical failure)

---

## ✨ Key Features

### Issue Detection
- 🚨 **Duplicate Detection** - Finds multiple DM entries for same VM disk
- ⚠️ **Tombstone Detection** - Identifies orphaned entries from deleted VMs/disks
- 📊 **VM-Centric Analysis** - Shows health status per VM
- 🎯 **Accurate Counting** - No double-counting of issues

### Reporting & Monitoring
- 📧 **HTML Email Reports** via Mailjet API
- 🎨 **Color-Coded Severity** (Red=Critical, Yellow=Warning, Green=Good)
- 📈 **Performance Metrics** (CPU, RAM, uptime, storage)
- 🏆 **Health Grade** (A+ to F based on issue severity)

### Safe Interactive Cleanup
- 🔒 **Read-only by default** - No changes without consent
- 📝 **Detailed explanations** for each issue before removal
- 🎯 **Priority handling** - Critical duplicates cleaned first
- ✅ **User confirmation** required for each action

---

## 🎯 Understanding Critical Issues

### 🚨 Duplicate Device Mapper Entries (CRITICAL)

**Example Problem:**
```
VM 169 config shows: scsi0: ssd-ha01:vm-169-disk-0

Device mapper has:
  ssd--ha01-vm--169--disk--0  ✓ (correct)
  ssd--ha01-vm--169--disk--0  ❌ (DUPLICATE!)
```

**Impact:**
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
wget https://raw.githubusercontent.com/keithrlucier/proxmox-dm-health-check/main/Proxmox_DM_Cleanup_v31.sh

# Make executable
chmod +x Proxmox_DM_Cleanup_v31.sh

# Run analysis
./Proxmox_DM_Cleanup_v31.sh
```

### Option 2: Manual Creation
```bash
# Create/edit the script
nano /root/Proxmox_DM_Cleanup_v31.sh

# Make executable
chmod +x /root/Proxmox_DM_Cleanup_v31.sh

# Run analysis
./Proxmox_DM_Cleanup_v31.sh
```

---

## 🕒 Schedule Daily Checks (10 PM)

```bash
crontab -e
```

Add this line:
```bash
0 22 * * * /root/Proxmox_DM_Cleanup_v31.sh > /var/log/proxmox_dm_check.log 2>&1
```

---

## 📊 Sample Output

### VM Status Section
```
🖥️  VM STATUS ON THIS NODE
=========================================

VM ID    NAME                           STATUS       DM HEALTH
-----    ----                           ------       ---------
115      Windows Server 2019            🟢 Running   🚨 2 disk(s) DUPLICATED!
125      Ubuntu 22.04 LTS               ⚪ Stopped   ✅ Clean
138      Development Server             ⚪ Stopped   ⚠️ 1 tombstone(s)
145      Database Server                🟢 Running   ✅ Clean
191      Web Server                     ⚪ Stopped   ✅ Clean

Additionally, tombstones exist for 69 non-existent VM IDs:
   VM 169    : 2 tombstone(s) ❌ VM DOES NOT EXIST
   VM 127    : 2 tombstone(s) ❌ VM DOES NOT EXIST
```

### Critical Issue Detection
```
🔍 ANALYZING DEVICE MAPPER ISSUES
=========================================

Step 3: Detecting DUPLICATE entries (critical issue!)...

❌ CRITICAL DUPLICATE: VM 115 disk-0 has 2 device mapper entries!
   → This WILL cause unpredictable behavior and VM failures!
      - ssd--ha01-vm--115--disk--0
      - ssd--ha01-vm--115--disk--0

📊 ANALYSIS SUMMARY
=========================================
   Total device mapper entries: 177
   Valid entries: 4
   Duplicate entries: 2 🚨 CRITICAL ISSUE!
   Tombstoned entries: 171 ⚠️ WILL BLOCK DISK CREATION!
   Total issues: 173
```

---

## 🔒 Safety Features

### What Gets Cleaned
- ✅ **Duplicate DM entries** (keeps first, removes extras)
- ✅ **Tombstoned entries** (orphaned with no VM config)

### What's Protected
- ✅ **VM disk data** - Never touched
- ✅ **VM configurations** - Read-only access
- ✅ **Active VMs** - Never modified
- ✅ **Storage backends** - Unaffected

### Cleanup Priority
1. **DUPLICATES FIRST** - Critical issues that break VMs
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
  - 🚨 CRITICAL: Duplicates found
  - ⚠️ WARNING: Tombstones only
  - ✅ EXCELLENT: No issues
- **Color-coded health status**
- **VM-specific issue breakdown**
- **Clear action items**
- **GitHub repository links** for documentation and support

---

## 🧪 Testing the Script

### Create Test Duplicate (Use Carefully!)
```bash
# Create duplicate entries for testing
dmsetup create test--vm--999--disk--0 --table '0 204800 linear /dev/sda 0'
dmsetup create test2--vm--999--disk--0 --table '0 204800 linear /dev/sda 0'
```

### Create Test Tombstone
```bash
# Create orphaned entry
dmsetup create test--vm--888--disk--0 --table '0 204800 linear /dev/sda 0'
```

### Cleanup Test Entries
```bash
dmsetup remove test--vm--999--disk--0
dmsetup remove test2--vm--999--disk--0
dmsetup remove test--vm--888--disk--0
```

---

## 🆕 Version 31 Improvements

### Latest Updates (v31)
- 🔗 **GitHub Integration** - Added repository links to email reports
- 📄 **Easy Access** - Direct links to documentation from email footer
- 🐛 **Bug Tracking** - Users can report issues directly from email

### Major Features (v30)
- 🎯 **Focus on DUPLICATES** as the critical issue
- 📊 **VM Status Dashboard** showing health per VM
- 🔢 **Accurate counting** - no more double-counting
- 🏷️ **Simplified terminology** - Valid, Duplicate, or Tombstoned only
- 🎨 **Visual health indicators** (🚨, ⚠️, ✅)
- 📧 **Enhanced email subjects** clearly indicate severity

### Removed Confusion
- ❌ No more "stale" terminology
- ❌ No more "orphaned" (now "tombstoned")
- ❌ No double-counting issues
- ❌ No ambiguous health grades

### Better Prioritization
- Duplicates = Automatic F grade
- Duplicates cleaned first in interactive mode
- Clear severity indicators throughout

---

## 🛠 Dependencies

- Proxmox tools: `qm`, `pct`, `dmsetup`
- Linux tools: `awk`, `sed`, `grep`, `sort`, `uniq`
- Email: `curl`, Mailjet API
- Optional: `top`, `free`, `df`, `uptime`

---

## 🚨 Common Issues & Solutions

### VM Won't Start - "Device Busy"
**Cause**: Duplicate or tombstoned entries  
**Fix**: Run script, clean issues for that VM

### Can't Create VM with Specific ID
**Cause**: Tombstoned entries from old VM  
**Fix**: Run script, remove tombstones

### VM Behaving Unpredictably
**Cause**: DUPLICATE entries (critical!)  
**Fix**: Run script IMMEDIATELY

### After Failed Migration
**Symptom**: Leftover entries on source  
**Fix**: Run script on source node

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

**Keywords**: Proxmox duplicate device mapper, VM startup failures, device busy errors, tombstoned entries, VM disk conflicts, Proxmox storage cleanup, device mapper troubleshooting, VM health monitoring

---

## 🔗 Quick Links

- [GitHub Repository](https://github.com/keithrlucier/proxmox-dm-health-check)
- [Full Documentation](https://github.com/keithrlucier/proxmox-dm-health-check/blob/main/Documentation.md)
- [Issue Tracker](https://github.com/keithrlucier/proxmox-dm-health-check/issues)
- [Latest Release](https://github.com/keithrlucier/proxmox-dm-health-check/releases)

---

**Remember**: Duplicates are CRITICAL and require immediate attention! 🚨