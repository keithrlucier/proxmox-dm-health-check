# Proxmox Device Mapper Health Check

**Enterprise Device Mapper Management for Proxmox Virtual Environment**

Version 35 | Enterprise Edition  
Author: Keith R. Lucier — ProSource Technology Solutions

---

## Executive Summary

The Proxmox Device Mapper Health Check is an enterprise-grade diagnostic and remediation tool designed to identify and resolve critical device mapper inconsistencies in Proxmox VE clusters. The tool addresses a fundamental issue in Proxmox environments where device mapper entries fail to be properly cleaned up, causing virtual machine failures and operational disruptions.

### Primary Capabilities

- **Critical Issue Detection**: Identifies duplicate device mapper entries that cause VM failures
- **Orphaned Entry Management**: Detects and removes stale entries blocking VM operations
- **Enterprise Reporting**: Generates comprehensive HTML reports with actionable insights
- **Automated Monitoring**: Integrates with cron for continuous health assessment
- **Safe Remediation**: Provides controlled, user-confirmed cleanup procedures

### Business Impact

Device mapper issues in Proxmox can result in:
- Virtual machine startup failures
- Service availability disruptions
- Resource allocation conflicts
- Operational inefficiencies requiring manual intervention

This tool provides automated detection and remediation capabilities to minimize these impacts.

---

## Technical Overview

### Problem Domain

Proxmox VE utilizes Linux device mapper for virtual disk management. Due to persistent bugs in the cleanup process, device mapper entries often remain after VM deletion or migration, creating two primary issue types:

1. **Duplicate Entries**: Multiple device mapper entries for the same VM disk on the same storage pool
2. **Orphaned Entries**: Device mapper entries without corresponding VM configurations

### Key Technical Context

- VM IDs are automatically assigned using the lowest available number (range: 100-1,000,000)
- Device mapper entries should be automatically removed when VMs stop/delete (but often aren't due to bugs)
- Entries persist through system reboots and require manual cleanup
- Proxmox 8.2.2+ has a regression creating entries for ALL LVM volumes at boot

### Solution Architecture

The tool implements a multi-phase approach:

1. **Discovery Phase**: Comprehensive inventory of VMs and device mapper entries
2. **Analysis Phase**: Cross-reference validation between VM configurations and device mapper state
3. **Reporting Phase**: Generation of detailed health reports with severity classification
4. **Remediation Phase**: Optional interactive cleanup with safety controls

---

## Disclaimer and Support

**IMPORTANT**: This software is provided "AS IS" without warranty of any kind, express or implied. Use of this tool is entirely at your own risk. The author and ProSource Technology Solutions assume no liability for any damages or losses resulting from the use of this software.

### Support Model

- **Commercial Support**: Not available
- **Community Resources**: GitHub repository for issue tracking and documentation
- **Warranty**: None provided
- **Liability**: User assumes all risks

### Prerequisites for Use

- Current backups of all virtual machines
- Understanding of Proxmox storage architecture
- Root access to Proxmox nodes
- Testing in non-production environment recommended

---

## Installation and Deployment

### System Requirements

- Proxmox VE 6.x or higher
- Root access to Proxmox nodes
- Standard Linux utilities (pre-installed on Proxmox)
- Optional: Mailjet API credentials for email reporting

### Installation Methods

#### Method 1: Direct Download
```bash
# Download from GitHub repository
wget https://raw.githubusercontent.com/keithrlucier/proxmox-dm-health-check/main/Proxmox_DM_Cleanup_v35.sh

# Set execution permissions
chmod +x Proxmox_DM_Cleanup_v35.sh
```

#### Method 2: Manual Deployment
```bash
# Create script location
nano /root/Proxmox_DM_Cleanup_v35.sh

# Copy script content and save
# Set execution permissions
chmod +x /root/Proxmox_DM_Cleanup_v35.sh
```

### Configuration

Email reporting configuration (edit script header):
```bash
MAILJET_API_KEY="your-api-key"
MAILJET_API_SECRET="your-api-secret"
FROM_EMAIL="noc@organization.com"
FROM_NAME="Proxmox Health Monitor"
TO_EMAIL="infrastructure-team@organization.com"
```

---

## Usage and Operations

### Execution Modes

#### 1. Analysis Mode (Default)
```bash
./Proxmox_DM_Cleanup_v35.sh
```
Performs read-only analysis and generates reports without making changes.

#### 2. Interactive Cleanup Mode
When issues are detected, the script offers interactive remediation:
- Prioritizes critical issues (duplicates) over warnings (orphans)
- Requires explicit confirmation for each action
- Provides detailed explanation before each operation

### Automated Monitoring

Configure scheduled execution via cron:
```bash
# Daily execution at 22:00
0 22 * * * /root/Proxmox_DM_Cleanup_v35.sh > /var/log/proxmox_dm_check.log 2>&1
```

### Output Interpretation

#### Health Grades
- **A+**: No issues detected
- **B**: 1-5 orphaned entries
- **C**: 6-20 orphaned entries  
- **D**: 21-50 orphaned entries
- **F**: Any duplicate entries OR 50+ orphaned entries

#### VM Status Matrix
```
VM ID    NAME                           STATUS       DM HEALTH
-----    ----                           ------       ---------
169      Production Database            Running      Clean
170      Web Server                     Running      [!] 1 storage:disk(s) DUPLICATED
171      Backup Server                  Stopped      [!] 2 tombstone(s)
```

---

## Technical Implementation

### Issue Detection Algorithms

#### Duplicate Detection
Identifies multiple device mapper entries for the same combination of:
- VM ID
- Storage Pool  
- Disk Number

Only entries matching all three criteria are classified as duplicates.

#### Orphan Detection
Classifies entries as orphaned when:
- Associated VM does not exist on the node
- VM exists but lacks the specific disk configuration
- Storage pool reference does not match VM configuration

### Safety Mechanisms

1. **Read-Only Default**: No modifications without explicit user consent
2. **Open Handle Detection**: Verifies device "Open count" is 0 before removal (via `dmsetup info`)
3. **Dependency Ordering**: Removes child devices (e.g., vm-disk-0p1) before parent devices (vm-disk-0)
4. **Case-Insensitive Matching**: Handles storage pool naming variations (T1-HA07 vs t1--ha07)
5. **Storage Pool Verification**: Only identifies true duplicates on the same storage pool
6. **Confirmation Required**: Each removal action requires explicit user confirmation

### Known Limitations and Bugs

- **Automatic Cleanup Failures**: Device mapper entries frequently fail to be removed when VMs are deleted
- **Proxmox 8.2.2 Regression**: Creates device mapper entries for ALL LVM volumes at boot, not just active VMs
- **Cluster Synchronization**: Shared storage environments may have orphaned entries on multiple nodes
- **Race Conditions**: VM ID assignment lacks atomic reservation, causing conflicts during simultaneous VM creation
- **Partition Dependencies**: Child devices (e.g., vm-disk-0p1) can keep parent devices from being removed
- **LVM Autoactivation**: In clustered environments, causes entries to be recreated after cleanup

---

## Version History

### Version 35 (Current)
- Implemented case-insensitive storage pool comparison
- Resolved false positive detections with uppercase storage names
- Enhanced compatibility with mixed-case storage configurations

### Version 34
- Added storage pool verification to orphan detection
- Implemented support for NVMe and multipath disk types
- Enhanced email report JSON encoding

### Version 33
- Corrected storage pool extraction methodology
- Improved duplicate detection accuracy

### Version 32
- Resolved false positive duplicate detection
- Implemented storage-aware duplicate identification

### Previous Versions
See GitHub repository for complete version history.

---

## Best Practices

### Pre-Deployment
1. Verify current backup status
2. Document existing VM configurations
3. Test in isolated environment
4. Review script output in analysis mode

### Operational Guidelines
1. Run analysis before cleanup
2. Address duplicate entries immediately (critical priority)
3. Schedule regular orphan cleanup during maintenance windows
4. Monitor trends over time
5. Clean orphaned entries immediately after VM deletions

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

### Post-Cleanup Verification
1. Verify VM functionality
2. Check storage accessibility  
3. Confirm issue resolution via re-running analysis
4. Document actions taken

---

## Troubleshooting

### Common Issues

#### VM Creation Fails - "Device Busy"
- **Cause**: Orphaned entries blocking VM ID reuse
- **Resolution**: Execute cleanup for specific VM ID

#### Unpredictable VM Behavior
- **Cause**: Duplicate device mapper entries
- **Resolution**: Immediate cleanup required

#### High Orphan Count
- **Cause**: Improper VM deletion procedures
- **Resolution**: Review VM lifecycle management processes

### Diagnostic Commands

```bash
# List all device mapper entries
dmsetup ls | grep vm--

# Check specific VM entries
dmsetup ls | grep vm--119

# Find conflicting entries for a VMID
dmsetup table | grep <VMID>

# Verify entry details (check Open count)
dmsetup info <device-name>

# View device relationships
dmsetup ls --tree
```

---

## Security Considerations

- Script requires root privileges
- Email reports may contain infrastructure details
- No VM data is accessed or modified
- Only device mapper metadata is affected

---

## Author Information

**Keith R. Lucier**  
ProSource Technology Solutions  
Email: keithrlucier@gmail.com  
LinkedIn: [https://www.linkedin.com/in/keithrlucier/](https://www.linkedin.com/in/keithrlucier/)

---

## Resources

- **Source Code**: [https://github.com/keithrlucier/proxmox-dm-health-check](https://github.com/keithrlucier/proxmox-dm-health-check)
- **Documentation**: [https://github.com/keithrlucier/proxmox-dm-health-check/blob/main/Documentation.md](https://github.com/keithrlucier/proxmox-dm-health-check/blob/main/Documentation.md)
- **Issue Tracking**: [https://github.com/keithrlucier/proxmox-dm-health-check/issues](https://github.com/keithrlucier/proxmox-dm-health-check/issues)

---

## License

This project is licensed under the MIT License. See the [LICENSE](https://github.com/keithrlucier/proxmox-dm-health-check/blob/main/LICENSE) file for details.

---

**Document Classification**: Public  
**Last Updated**: January 2025  
**Version**: 35