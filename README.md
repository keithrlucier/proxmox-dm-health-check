# Proxmox Device Mapper Health Check

**Enterprise Device Mapper Management for Proxmox Virtual Environment**

Version 36 | MIT License | Proxmox VE 6.x+

## Overview

The Proxmox Device Mapper Health Check tool identifies and safely resolves device mapper inconsistencies that cause VM failures in Proxmox VE environments. It detects duplicate and orphaned device mapper entries that prevent VM operations and provides controlled remediation with comprehensive safety checks.

### What's New in v36

🛡️ **Device Open Safety Protection**: Automatically detects and protects in-use devices from removal, preventing disruption to running VMs.

### Key Features

- **Critical Issue Detection**: Identifies duplicate device mapper entries causing VM failures
- **Orphaned Entry Management**: Finds and removes entries blocking VM ID reuse
- **Safety First**: NEW - Checks device open status before any removal attempt
- **Enterprise Reporting**: HTML email reports with health grades and actionable insights
- **Interactive Cleanup**: User-confirmed remediation with clear explanations
- **Automated Monitoring**: Cron-compatible for scheduled health checks

## Quick Start

### Installation

```bash
# Download latest version
# Note: Replace with actual URL from releases or repository
curl -O https://github.com/keithrlucier/proxmox-dm-health-check/releases/latest/download/proxmox_dm_v36.sh
# OR manually download from the repository

chmod +x proxmox_dm_v36.sh

# Configure email reporting (optional)
# Edit the script header with your Mailjet API credentials
```

### Basic Usage

```bash
# Run analysis only (safe, read-only)
./proxmox_dm_v36.sh

# When prompted, choose interactive cleanup
Do you want to interactively clean up these issues? (y/N): y
```

### Automated Monitoring

```bash
# Add to crontab for daily checks
0 2 * * * /root/proxmox_dm_v36.sh > /var/log/proxmox_dm_check.log 2>&1
```

## Understanding the Issues

### Why This Tool Exists

Proxmox has persistent bugs where device mapper entries aren't properly cleaned up when VMs are deleted. This causes:

- **VM Creation Failures**: "Device or resource busy" errors when Proxmox tries to reuse VM IDs
- **Duplicate Entries**: Multiple device mapper entries for the same disk causing unpredictable behavior
- **Orphaned Entries**: Leftover entries that persist through reboots and block operations

### Important Context

- Proxmox automatically assigns the lowest available VM ID (default range: 100-1,000,000)
- Device mapper entries persist across reboots - manual cleanup is required
- Proxmox 8.2.2+ has a regression that creates entries for ALL LVM volumes at boot

## Safety Features

### Device Open Protection (NEW in v36)

The tool now checks if devices are in use before attempting removal:

```
🚨 DUPLICATE: ssd--ha01-vm--169--disk--0 [DEVICE IS CURRENTLY OPEN/IN USE]
   → Cannot remove while device is in use. Stop the VM first.
```

### Multiple Safety Layers

1. **Read-Only by Default**: Analysis mode makes no changes
2. **Device Open Check**: Uses `dmsetup info`, `lsof`, and `fuser` to verify device status
3. **User Confirmation**: Every removal requires explicit approval
4. **Running VM Protection**: Automatically skips devices belonging to active VMs

## Output Interpretation

### Health Grades

- **A+**: No issues detected
- **B**: 1-5 orphaned entries
- **C**: 6-20 orphaned entries
- **D**: 21-50 orphaned entries
- **F**: Any duplicate entries OR 50+ orphaned entries

### Sample Output

```
📊 ANALYSIS SUMMARY
   Total device mapper entries: 245
   Valid entries: 238 ✅
   Duplicate entries: 2 🚨 CRITICAL ISSUE!
   Tombstoned entries: 5 ⚠️ WILL BLOCK DISK CREATION!
   Devices currently in use: 3
   Total issues: 7
```

## Common Scenarios

### Scenario 1: VM Creation Fails

**Symptom**: "Device or resource busy" error when creating a new VM

**Cause**: Orphaned entries exist for the VM ID that Proxmox is trying to assign

**Solution**: Run this tool to clean orphaned entries

### Scenario 2: VM Behaves Unpredictably

**Symptom**: VM performance issues, failed operations, or data corruption risks

**Cause**: Duplicate device mapper entries for the same disk

**Solution**: Immediate cleanup required - duplicates are critical issues

## Best Practices

1. **Run After VM Deletions**: Clean up immediately to prevent future ID conflicts
2. **Schedule Regular Checks**: Use cron for daily monitoring
3. **Stop VMs Before Cleanup**: For best results, stop affected VMs before remediation
4. **Monitor Trends**: Track issue counts over time to identify systemic problems

## Requirements

- Proxmox VE 6.x or higher
- Root access to Proxmox nodes
- Optional: Mailjet API for email reports
- Optional: `lsof` and `fuser` for enhanced device detection

## Documentation

For detailed information, see:
- [Full Documentation](Documentation.md) - Comprehensive guide with technical details
- [Issue Tracker](https://github.com/keithrlucier/proxmox-dm-health-check/issues) - Report bugs or request features

## Troubleshooting

### Quick Diagnostics

```bash
# List all VM device mapper entries
dmsetup ls | grep vm--

# Check if a device is in use
dmsetup info <device-name> | grep "Open count"

# Find entries for a specific VM
dmsetup ls | grep vm--119
```

### Need Help?

1. Check the [full documentation](Documentation.md) for detailed troubleshooting
2. Review [existing issues](https://github.com/keithrlucier/proxmox-dm-health-check/issues)
3. Ensure you're running the latest version (v36)

## Disclaimer

This software is provided "AS IS" without warranty of any kind. Use at your own risk. Always maintain current backups before performing cleanup operations.

## Author

**Keith R. Lucier**  
[LinkedIn](https://www.linkedin.com/in/keithrlucier/) | [GitHub](https://github.com/keithrlucier)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Version**: 36  
**Last Updated**: November 2024