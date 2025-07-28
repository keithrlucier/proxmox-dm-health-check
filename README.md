# 🧹 Proxmox DM Setup Table Health & Cleanup Toolkit

**Author**: Keith R Lucier — IT Professional with 30+ years of experience\
**Version**: 27\
**Purpose**: Analyze and clean up stale `dmsetup` table entries on Proxmox nodes with **enhanced config validation**

---

## 🚀 Overview

This toolkit is a safe, smart, and professionally engineered Bash script designed to audit, score, and optionally clean up **stale Proxmox DM Setup Table entries** with **NEW Config Validation capabilities**. It's perfect for clusters and standalone nodes where device-mapper cleanup is often overlooked, and now includes **comprehensive VM configuration validation** to prevent startup failures caused by configuration mismatches.

The script offers detailed email-based health reports including VM mappings, host stats, config validation results, and cleanup options.

---

## 🔍 What It Does

### Core Analysis
- ✅ Scans all `dmsetup` entries (e.g. `/dev/mapper/vm--<id>--disk--0`)
- ✅ Identifies and flags **stale entries** (devices not tied to running VMs)
- ✅ Grades system performance (CPU, RAM, load, stale count, config issues)
- ✅ Sends a professional HTML health report via Mailjet API
- ✅ Offers safe interactive cleanup (prompt-based)

### 🆕 NEW: Config Validation Module (v27)
- 🔍 **Cross-references VM configurations** against actual device mapper entries
- 🚨 **Detects orphaned entries** that don't match any VM configuration
- 📋 **Identifies duplicate entries** for the same logical disk
- ❓ **Tracks missing entries** where VM config expects disk but no DM entry exists
- 🛡️ **Prevents VM startup failures** caused by configuration corruption
- 🔧 **Enhanced disk type support** - EFI, TPM, unused disks, and standard VM disks

---

## ✨ Key Features

### Traditional Features
- 📊 **DM Setup Table Health Audit**
- 📉 **Performance Grading System** (A+ to D)
- 📨 **Automated Email Reports** (Mobile-responsive, color-coded HTML)
- 🔒 **Safe & Non-destructive Cleanup Workflow**
- 🖥️ **System Insights**: RAM, swap, VM counts, container stats, ZFS, LVM, I/O load, top procs, and more

### 🆕 NEW in Version 27
- 🔍 **Config Validation Module** - Comprehensive VM config vs DM entry validation
- 🚨 **Orphaned Entry Detection** - Finds entries that don't match any VM configuration
- 📋 **Duplicate Entry Detection** - Identifies multiple entries for same disk
- ❓ **Missing Entry Tracking** - VM config expects disk but no DM entry exists
- 🛡️ **Enhanced Safety Explanations** - Detailed context for each cleanup action
- 🔧 **All Disk Type Support** - EFI disks, TPM disks, unused disks, standard VM disks
- 📧 **Enhanced Email Reports** - Config validation results prominently displayed
- 🔄 **Two-Phase Interactive Cleanup** - Separate handling for stale entries vs config issues

---

## 🎯 Why Config Validation Matters

**The Problem:** During VM restores, disk operations, or storage migrations, device mapper entries can become mismatched with VM configurations. This causes:
- ❌ VM startup failures with "Device or resource busy" errors
- ❌ Storage conflicts preventing VM migration
- ❌ Orphaned entries consuming system resources

**The Solution:** Version 27's Config Validation Module catches these exact mismatches, identifying:
- **Orphaned entries** that don't belong to any VM configuration
- **Duplicate entries** pointing to the same logical disk
- **Missing entries** where configuration expects disks that don't exist

This **prevents the exact VM startup corruption scenario** that requires manual `dmsetup` investigation.

---

## 📁 Installation

```bash
nano /root/Proxmox_DM_Cleanup_v27.sh
chmod +x /root/Proxmox_DM_Cleanup_v27.sh
./Proxmox_DM_Cleanup_v27.sh
```

---

## 🕒 Schedule the Script (Nightly at 10 PM)

```bash
crontab -e
```

Choose nano (option 1 if prompted), then add this at the bottom:

```bash
0 22 * * * /root/Proxmox_DM_Cleanup_v27.sh > /var/log/proxmox_dmcheck.log 2>&1
```

---

## 🧼 To Remove the Job and Script

```bash
crontab -e        # Then delete the cron line
rm /root/Proxmox_DM_Cleanup_v27.sh
```

---

## 🔒 Safety First

### Traditional Safety
- Script is **read-only by default**
- Prompts user **before** removing any stale entry
- Never touches active VMs or disk data
- Stale DM entries are removed **only if VM is not running** on the node

### 🆕 Enhanced Safety (v27)
- **Config validation** provides detailed explanations for each issue type
- **Two-phase cleanup** separates traditional stale entries from config issues
- **Enhanced user prompts** with safety information for each action
- **Orphaned entry removal** is safe and prevents future conflicts
- **Debug output** allows verification of parsing accuracy

> ✅ **Shutdown VMs** are flagged as stale (since Proxmox will recreate entries on boot)\
> ✅ **Orphaned entries** are flagged when they don't match any VM configuration\
> ✅ **Entries persist across reboots** — Proxmox does not clean these automatically\
> ✅ **Config mismatches** are safely identified and can be resolved interactively

---

## 🧪 Testing

### Traditional Stale Entry Testing
- **Live test**: migrate a VM away, check for leftover DM entries
- **Synthetic test**:

```bash
fallocate -l 100M /tmp/test.img
losetup /dev/loop10 /tmp/test.img
dmsetup create test--vm--999--disk--0 --table '0 204800 linear /dev/loop10 0'
```

### 🆕 Config Validation Testing
- **Orphaned entry test**: Create DM entry for non-existent VM (use synthetic test above)
- **Missing entry test**: Stop a VM and observe config expects disks but no DM entries
- **Live test**: Perform VM restore and check for config mismatches

Clean up synthetic test with:
```bash
dmsetup remove test--vm--999--disk--0
losetup -d /dev/loop10
rm /tmp/test.img
```

---

## 📊 Sample Output (New in v27)

```
CONFIG VALIDATION MODULE
=========================================

Checking for orphaned device mapper entries...
ORPHANED: ssd--ha01-vm--163--disk--0 (VM 163 exists but disk 0 not in config)
ORPHANED: t1--ha04-vm--151--disk--1 (VM 151 does not exist on this node)

Checking for duplicate device mapper entries...
(No duplicates found)

Checking for missing device mapper entries...
MISSING: VM 125 disk 0 (SSD-HA01:vm-125-disk-0) has no device mapper entry

Config Validation Summary:
   Orphaned DM entries: 2
   Duplicate DM entries: 0
   Missing DM entries: 1
   Total config issues: 3

Status: CONFIG ISSUES DETECTED - Review recommended
```

---

## 🛠 Dependencies

- Proxmox tools: `qm`, `pct`, `pvecm`
- Linux core tools: `dmsetup`, `top`, `free`, `lscpu`, `ps`, `uptime`, etc.
- Optional: `zpool`, `vgs`, `mpstat`, `bc`, `curl`, `mailjet API`
- **NEW**: Access to VM config files in `/etc/pve/qemu-server/`

---

## 📬 Mailjet Setup (for email reporting)

### What Is Mailjet?

[Mailjet](https://www.mailjet.com) is an email API and SMTP service provider. It allows you to programmatically send emails using HTTP requests or SMTP — perfect for automated reports like the ones this script generates.

### Step-by-Step: Getting Started with Mailjet

1. **Create a Free Account**\
   Go to [https://app.mailjet.com/signup](https://app.mailjet.com/signup) and sign up for a free account.

2. **Generate API Credentials**\
   After logging in:

   - Navigate to **Account Settings → API Keys**
   - Click **"Create API Key"**
   - Copy both the **API Key** and **Secret Key** securely

3. **Verify Sender Email**\
   Go to **Senders & Domains** and:

   - Add your `FROM_EMAIL` address (e.g., `automation@yourdomain.com`)
   - Mailjet will send a verification email — confirm it before proceeding

4. **Optional: Domain Authentication**\
   For better deliverability, you can also add DNS records to authenticate your domain with Mailjet.

### Embed Your Mailjet Info in the Script

At the top of your script file (`/root/Proxmox_DM_Cleanup_v27.sh`), add:

```bash
MAILJET_API_KEY="<your-mailjet-api-key>"
MAILJET_API_SECRET="<your-mailjet-api-secret>"
FROM_EMAIL="automation@yourdomain.com"
FROM_NAME="ProxMox DMSetup Health Check"
TO_EMAIL="you@example.com"
```

> 🔒 **Security Tip:** Avoid sharing or hardcoding these keys outside secure environments.

After saving changes, run the script. If all is configured correctly, it will send a fully styled HTML email report to your `TO_EMAIL` inbox with **enhanced config validation results**.

---

## 🔍 Understanding the Issue Types

### **Stale Entries** (Traditional)
- VM is not running but still has device mapper entries
- **Safe to remove** - entries recreated when VM starts

### 🆕 **Orphaned Entries** (New in v27)
- Device mapper entries that don't match any VM configuration
- **These cause VM startup failures** - should be removed
- Often result from restore corruption or failed migrations

### 🆕 **Duplicate Entries** (New in v27) 
- Multiple device mapper entries for the same logical disk
- Can cause "device busy" errors
- May require investigation to determine which entry to keep

### 🆕 **Missing Entries** (New in v27)
- VM configuration expects a disk but no device mapper entry exists
- Usually normal for stopped VMs
- Entries automatically recreated when VM starts

---

## 📧 Enhanced Email Reports (v27)

The email reports now include:
- 📊 **Config Validation Results** section with detailed breakdown
- 🎨 **Color-coded metrics** showing severity of each issue type
- 📋 **Specific entries** causing problems with VM details
- 🔧 **Action recommendations** for each type of issue
- 📈 **Enhanced performance grading** that includes config issues

---

## 📎 Full Documentation

See the comprehensive documentation for:

- In-depth DM Setup Table explanation  
- **NEW: Config Validation Module details**
- Safety model and enhanced safety measures
- System behavior on VM shutdown/migration
- **NEW: Issue type explanations and remediation**
- Visuals and output breakdowns
- Full feature matrix

---

## 🆕 Version 27 Improvements

### New Features
- **Config Validation Module** - Comprehensive VM config vs DM entry validation
- **Enhanced Disk Type Support** - EFI, TPM, unused disks
- **Orphaned Entry Detection** - Finds entries that don't match any VM config
- **Duplicate Entry Detection** - Identifies multiple entries for same disk
- **Missing Entry Tracking** - VM config expects disk but no DM entry
- **Two-Phase Interactive Cleanup** - Separate handling for different issue types
- **Enhanced Email Reports** - Config validation results prominently displayed

### Improvements  
- **Better Performance Grading** - Now includes config issues in health score
- **Enhanced Safety Information** - Detailed explanations for each cleanup action
- **Debug Output** - Better troubleshooting and verification capabilities

### Bug Fixes
- **Bash Syntax Errors** - Fixed variable declaration issues
- **Config Parsing Issues** - Now correctly handles all Proxmox disk types
- **Compatibility Improvements** - Better support for different bash versions

---

## 👨‍💻 Author

**Keith R. Lucier**\
Senior Engineer & Systems Administrator | Microsoft Ecosystem Specialist | Power Platform Developer\
🔗 [LinkedIn Profile](https://www.linkedin.com/in/keithrlucier/)

Providing frictionless, responsive, and secure business technology solutions, Keith is a seasoned IT professional with over 30 years of experience leading enterprise environments and delivering results at scale. He has served as a former IT Director for an organization with over 500 employees and currently specializes in:

- Microsoft 365 and Azure ecosystem administration
- Power Platform development and automation
- AI & hybrid cloud integrations
- Enterprise IT strategy and systems modernization
- **Proxmox virtualization and storage management**
- Disaster recovery planning and implementation

Keith combines a deep understanding of business needs with expert-level systems knowledge to architect responsive and resilient infrastructures that prioritize uptime, security, and user empowerment.

---

## ⚠️ Disclaimer

This script is provided as-is. Ensure you understand your storage architecture before using it in production environments. The config validation module enhances safety by identifying potential issues before they cause problems.

---

## 📄 License

MIT

---

**Keywords**: Proxmox, DM Setup Table, stale device-mapper cleanup, virtual machine storage, Proxmox disk map, cluster health audit, config validation, VM startup troubleshooting, device mapper troubleshooting

