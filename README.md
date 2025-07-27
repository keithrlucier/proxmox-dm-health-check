# 🧹 Proxmox Device Mapper Health & Cleanup Toolkit

A powerful Bash-based toolkit for analyzing and safely cleaning up stale `dmsetup` table entries in Proxmox VE. Includes performance scoring, HTML email reporting, and interactive cleanup.

## 🔥 Features
- Detects stale vs. valid VM device-mapper entries
- Performance grading based on CPU/RAM usage and DM table health
- Professional HTML reporting via Mailjet
- Safe, interactive cleanup mode
- No data loss – zero-impact cleanup

## 📸 Screenshot Preview
![Report Sample](https://raw.githubusercontent.com/keithrlucier/proxmox-dm-health-check/main/sample-report.png)

## 🛠 Usage
```bash
bash Proxmox_DM_Cleanup_v26.sh
