# 🧹 Proxmox DM Setup Table Health & Cleanup Toolkit

**Author**: Keith R Lucier — IT Professional with 30+ years of experience\
**Version**: 26\
**Purpose**: Analyze and clean up stale `dmsetup` table entries on Proxmox nodes

---

## 🚀 Overview

This toolkit is a safe, smart, and professionally engineered Bash script designed to audit, score, and optionally clean up **stale Proxmox DM Setup Table entries**. It's perfect for clusters and standalone nodes where device-mapper cleanup is often overlooked, and offers a detailed email-based health report including VM mappings, host stats, and cleanup options.

---

## 🔍 What It Does

- ✅ Scans all `dmsetup` entries (e.g. `/dev/mapper/vm--<id>--disk--0`)
- ✅ Identifies and flags **stale entries** (devices not tied to running VMs)
- ✅ Grades system performance (CPU, RAM, load, stale count)
- ✅ Sends a professional HTML health report via Mailjet API
- ✅ Offers safe interactive cleanup (prompt-based)
- ✅ Designed with fail-safe logic and audit visibility

---

## ✨ Key Features

- 📊 **DM Setup Table Health Audit**
- 📉 **Performance Grading System** (A+ to D)
- 📨 **Automated Email Reports** (Mobile-responsive, color-coded HTML)
- 🔒 **Safe & Non-destructive Cleanup Workflow**
- 🖥️ **System Insights**: RAM, swap, VM counts, container stats, ZFS, LVM, I/O load, top procs, and more
- 🧠 **Built-in Explanations** for each stale entry before removal

---

## 📁 Installation

```bash
nano /root/Proxmox_DM_Cleanup_v26.sh
chmod +x /root/Proxmox_DM_Cleanup_v26.sh
./Proxmox_DM_Cleanup_v26.sh
```

---

## 🕒 Schedule the Script (Nightly at 10 PM)

```bash
crontab -e
```

Choose nano (option 1 if prompted), then add this at the bottom:

```bash
0 22 * * * /root/Proxmox_DM_Cleanup_v26.sh > /var/log/proxmox_dmcheck.log 2>&1
```

---

## 🧼 To Remove the Job and Script

```bash
crontab -e        # Then delete the cron line
rm /root/Proxmox_DM_Cleanup_v26.sh
```

---

## 🔒 Safety First

- Script is **read-only by default**
- Prompts user **before** removing any stale entry
- Never touches active VMs or disk data
- Stale DM entries are removed **only if VM is not running** on the node

> ✅ Shutdown VMs are flagged as stale (since Proxmox will recreate entries on boot) ✅ Entries persist across reboots — Proxmox does not clean these automatically

---

## 🧪 Testing

- **Live test**: migrate a VM away, check for leftover DM entries
- **Synthetic test**:

```bash
fallocate -l 100M /tmp/test.img
losetup /dev/loop10 /tmp/test.img
dmsetup create test--vm--999--disk--0 --table '0 204800 linear /dev/loop10 0'
```

Then run the script. Clean up after with:

```bash
dmsetup remove test--vm--999--disk--0
losetup -d /dev/loop10
rm /tmp/test.img
```

---

## 🛠 Dependencies

- Proxmox tools: `qm`, `pct`, `pvecm`
- Linux core tools: `dmsetup`, `top`, `free`, `lscpu`, `ps`, `uptime`, etc.
- Optional: `zpool`, `vgs`, `mpstat`, `bc`, `curl`, `mailjet API`

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
   - Click **“Create API Key”**
   - Copy both the **API Key** and **Secret Key** securely

3. **Verify Sender Email**\
   Go to **Senders & Domains** and:

   - Add your `FROM_EMAIL` address (e.g., `automation@yourdomain.com`)
   - Mailjet will send a verification email — confirm it before proceeding

4. **Optional: Domain Authentication**\
   For better deliverability, you can also add DNS records to authenticate your domain with Mailjet.

### Embed Your Mailjet Info in the Script

At the top of your script file (`/root/Proxmox_DM_Cleanup_v26.sh`), add:

```bash
MAILJET_API_KEY="<your-mailjet-api-key>"
MAILJET_API_SECRET="<your-mailjet-api-secret>"
FROM_EMAIL="automation@yourdomain.com"
FROM_NAME="ProxMox DMSetup Health Check"
TO_EMAIL="you@example.com"
```

> 🔒 **Security Tip:** Avoid sharing or hardcoding these keys outside secure environments.

After saving changes, run the script. If all is configured correctly, it will send a fully styled HTML email report to your `TO_EMAIL` inbox.

---

At the top of the script:

```bash
MAILJET_API_KEY="<your-api-key>"
MAILJET_API_SECRET="<your-api-secret>"
TO_EMAIL="you@example.com"
```

---

## 📎 Full Documentation

See [`DOCUMENTATION.md`](DOCUMENTATION.md) for:

- In-depth DM Setup Table explanation
- Safety model
- System behavior on VM shutdown/migration
- Visuals and output breakdowns
- Full feature matrix

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
- Disaster recovery planning and implementation

Keith combines a deep understanding of business needs with expert-level systems knowledge to architect responsive and resilient infrastructures that prioritize uptime, security, and user empowerment. Senior IT Professional with over 30 years of enterprise infrastructure experience

---

## ⚠️ Disclaimer

This script is provided as-is. Ensure you understand your storage architecture before using it in production environments.

---

## 📄 License

MIT

---

**Keywords**: Proxmox, DM Setup Table, stale device-mapper cleanup, virtual machine storage, Proxmox disk map, cluster health audit

