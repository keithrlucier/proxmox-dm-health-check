**Documentation: Proxmox Device Mapper Analysis and Cleanup Script (Version 26)**

---

### Overview

The **Proxmox Device Mapper Analysis and Cleanup Script** is a comprehensive Bash-based tool designed to assist system administrators in identifying and optionally removing stale device-mapper (DM) entries on a Proxmox Virtual Environment (PVE) host. The script performs real-time analysis, generates detailed HTML reports with system health metrics, and optionally delivers these reports via Mailjet email API. It also includes an interactive cleanup mode for safe manual removal of stale entries.

---

### Key Features

- Analyzes all DM entries related to VM disks
- Identifies and reports stale entries (DM devices referencing non-running VMs)
- Provides a summary of valid and stale entries
- Gathers extensive host health and performance metrics
- Grades system health (A+ to D) based on performance and stale entries
- Generates professional HTML email reports with dynamic visual indicators
- Sends reports using the Mailjet email API
- Interactive cleanup mode for safe stale entry removal with user confirmation

---

### Functions Breakdown

#### 1. **VM and DM Entry Discovery**

- Lists all running VMs on the host using `qm list`
- Retrieves all current DM entries matching `vm--<VMID>--disk`

> **Important:** Only VMs that are actively running on the node are considered valid. Powered-off or migrated VMs do not qualify their DM entries as valid.

#### 2. **DM Entry Classification**

- Each DM entry is parsed to extract its associated VM ID
- Entry is marked as:
  - **Valid**: VM is currently running on this host
  - **Stale**: VM is not running (entry is an orphaned leftover)

#### 3. **System Metrics Collection**

- Uptime, load averages, CPU usage and model, memory and swap usage
- Proxmox version, kernel version
- VM/container counts
- ZFS, LVM, network traffic, and disk usage statistics
- Boot time and top CPU-consuming processes

#### 4. **Performance Grading**

- Performance score calculated from:
  - CPU and RAM usage thresholds
  - Count of stale entries
- Letter grade (A+ to D) with associated color code

#### 5. **HTML Email Report Generation**

- Uses a template-style output with embedded system and DM entry data
- Styles and layout optimized for readability and mobile responsiveness
- Dynamic colors reflect health status and resource utilization

#### 6. **Email Delivery via Mailjet**

- HTML content embedded in a JSON payload
- Email includes subject with hostname, health grade, and status
- Text fallback provided for email clients without HTML support

#### 7. **Interactive Cleanup Mode**

- Optional mode prompted if stale entries exist
- Prompts user for each stale DM entry:
  - **(y)** remove entry
  - **(n)** skip
  - **(a)** auto-remove remaining without prompts
  - **(q)** quit
- Displays detailed explanation for each entry before prompting

---

### Installation on a Proxmox Node

1. **Copy the script to the node**

   ```bash
   scp Proxmox_DM_Cleanup_v26.sh root@<node-ip>:/usr/local/sbin/
   ```

2. **Set execution permissions**

   ```bash
   chmod +x /usr/local/sbin/Proxmox_DM_Cleanup_v26.sh
   ```

3. **Optionally add to PATH or use absolute path to run:**

   ```bash
   /usr/local/sbin/Proxmox_DM_Cleanup_v26.sh
   ```

---

### Scheduling with Cron

When you run `crontab -e` as root for the first time, you may be prompted to choose an editor. We recommend selecting option `1` for `/bin/nano` as the easiest option.

> Example Prompt:
>
> ```
> Select an editor.  To change later, run 'select-editor'.
>   1. /bin/nano        <---- easiest
>   2. /usr/bin/vim.basic
>   3. /usr/bin/vim.tiny
> Choose 1-3 [1]:
> ```

Once inside the crontab file (opened with nano), scroll past the existing commented explanation lines (which begin with `#`) to the bottom of the file. Then, on a new line, **add the following line** to run the script every night at 10 PM:

```bash
0 22 * * * /root/Proxmox_DM_Cleanup_v26.sh > /var/log/proxmox_dmcheck.log 2>&1
```

📌 This command means:

- `0` minute
- `22` hour (10 PM)
- `* * *` = every day, every month, every weekday

Save with `Ctrl+O`, press `Enter`, and exit with `Ctrl+X`.

If done correctly, this sets a scheduled job visible by running:

```bash
crontab -l
```

#### ❌ To Remove the Cron Job Later

Edit the crontab again:

```bash
crontab -e
```

Then delete the line containing the script command, save, and exit.

Since this script is intended to be run as root, and is stored in `/root/Proxmox_DM_Cleanup_v26.sh`, here are the exact commands you should use to automate or manage the script's execution.

#### ✅ Schedule the Script to Run Nightly at 10 PM

Edit the root user's crontab:

```bash
crontab -e
```

Add the following line to the end of the file:

```bash
0 22 * * * /root/Proxmox_DM_Cleanup_v26.sh > /var/log/proxmox_dmcheck.log 2>&1
```

#### ❌ Remove the Scheduled Cron Job

Edit the crontab again:

```bash
crontab -e
```

Then delete or comment out the line containing:

```bash
/root/Proxmox_DM_Cleanup_v26.sh
```

Save and exit.

---

### Suggested Commands (Run as Root)

These are the recommended commands for installing, executing, and removing the script:

```bash
nano /root/Proxmox_DM_Cleanup_v26.sh      # Edit or paste the script
chmod +x /root/Proxmox_DM_Cleanup_v26.sh  # Make it executable
./Proxmox_DM_Cleanup_v26.sh               # Run the script manually
rm /root/Proxmox_DM_Cleanup_v26.sh        # Remove the script completely
```

To completely remove the automation job and script from the system:

#### ❌ Remove the Cron Job

```bash
crontab -e
```

Then delete the line containing:

```bash
/root/Proxmox_DM_Cleanup_v26.sh
```

Save and exit with `Ctrl+O` and `Ctrl+X`.

#### 🧹 Remove the Script File

```bash
rm /root/Proxmox_DM_Cleanup_v26.sh
```

This fully removes both the scheduled task and the script itself from the system. These are the recommended commands for installing, executing, and removing the script:

```bash
nano /root/Proxmox_DM_Cleanup_v26.sh      # Edit or paste the script
chmod +x /root/Proxmox_DM_Cleanup_v26.sh  # Make it executable
./Proxmox_DM_Cleanup_v26.sh               # Run the script manually
rm /root/Proxmox_DM_Cleanup_v26.sh        # Remove the script completely (if no longer needed)
```

---

### Educational Note: Why Stale DM Entries Matter

Stale device-mapper entries are remnants left on a node when a VM is:

- Migrated to another node
- Shut down without full cleanup
- Manually removed from configuration but still referenced in storage

#### ⚠️ Impact of Unmaintained Stale Entries

- Can cause **"Device or resource busy"** errors
- May prevent new or migrated VMs from starting due to name conflicts
- Consume system resources and clutter device mappings

These entries **do not affect the storage data**, but keeping them around introduces unnecessary risk.

---

### Proxmox Behavior: What Entries Should Exist?

Only device-mapper entries **for VMs currently running on the host** should exist. Proxmox creates these entries when starting a VM. However, when VMs are shut down, migrated, or crash unexpectedly, their DM entries may linger.

#### How They Appear:

- When Proxmox starts a VM, it creates DM mappings for that VM’s disks.
- If the VM is live-migrated or fails, cleanup of these mappings doesn’t always occur.

#### What Happens If You Remove a DM Entry from a Stopped VM?

Removing a DM entry for a stopped VM is **safe** and will **not prevent** the VM from starting in the future. When the VM is started again, Proxmox will automatically recreate the appropriate DM entries based on its configuration and storage backend.

This is by design: Proxmox initializes all necessary device-mapper paths during the VM boot process. Stale entries from previously stopped or migrated VMs are not needed and only introduce clutter and potential conflict.

#### Do These Entries Clear After a Reboot?

No. A Proxmox node reboot does **not** automatically remove stale device-mapper entries. These entries are managed by the LVM subsystem (`lvm2`) and persist unless explicitly removed. Unless a cleanup mechanism is in place (like this script), stale entries will survive reboot and continue consuming system resources or cause name conflicts.

#### Why Proxmox Lacks Native Handling

Proxmox currently lacks built-in tooling to:

- Periodically detect and clean stale DM entries
- Alert administrators of orphaned mappings

This script fills that critical operational gap, providing both analysis and remediation with safety checks.

### Safety Measures

- **No changes** are made during analysis unless interactive cleanup is triggered
- **Stale entries** are safe to remove as they do **not** affect actual VM disk data
- Each action is confirmed by the user or auto-confirmed only if explicitly selected
- All sensitive operations are logged to terminal output for auditing

---

### Dependencies

- `qm`, `dmsetup`, `pvecm`, `zpool`, `vgs`, `pct`, `curl`, `mailjet API credentials`
- Optional tools: `mpstat`, `bc`, `dmidecode`, `top`, `ps`, `uptime`, `free`, `lscpu`

---

### Usage

1. **Execute Script on a Proxmox Node:**
   ```bash
   ./Proxmox_DM_Cleanup_v26.sh
   ```
2. **Review Analysis Output:**
   - Valid and stale DM entries
   - System metrics and performance grade
3. **Receive Email Report (auto-sent)**
4. **(Optional) Run Interactive Cleanup**
   - Choose `y`, `n`, `a`, or `q` for each stale entry

---

### Configuration

Located near the top of the script:

```bash
MAILJET_API_KEY="<your-mailjet-api-key>"
MAILJET_API_SECRET="<your-mailjet-api-secret>"
FROM_EMAIL="automation@yourdomain.com"
FROM_NAME="ProxMox DMSetup Health Check"
TO_EMAIL="recipient@yourdomain.com"
```

---

### Security Notes

- Mailjet API credentials are embedded in the script and should be rotated periodically
- Ensure only privileged users can access and execute the script

---

### File Cleanup

- Temporary files (`$TEMP_FILE`) used for subshell-safe processing are removed on exit

---

### Testing the Script

To safely generate stale device-mapper entries for testing purposes, use one of the following methods:

#### ✅ Method: Live Migrate a VM

1. Start a VM on **Node A**.
2. Live-migrate the VM to **Node B**:
   ```bash
   qm migrate <VMID> <Node-B>
   ```
3. Check Node A:
   - The DM entry for the VM may still be present.
   - This entry will now be considered stale and should be detected by the script.

#### ✅ Method: Manually Create a Fake Entry

Create a dummy DM mapping that simulates a stale VM disk:

```bash
dmsetup create test--vm--999--disk--0 --table '0 204800 linear /dev/sda 0'
```

- This entry will appear in `dmsetup ls` but has no associated running VM.
- The script will treat it as stale.

> ⚠️ Avoid forcibly deleting actual VM storage or modifying production VMs.

These controlled methods allow for safe script validation without risk to real workloads.

---

### Script Safety and Behavior

This script is designed with safety as the highest priority. Below is a summary of why it is considered safe for use in production environments:

#### ✅ Safe by Design

- **Read-Only by Default:** Running the script performs analysis and reporting only. No changes are made to the system unless the user explicitly opts into interactive cleanup.
- **Explicit User Prompts:** During cleanup, each stale entry is presented with context and requires user input (`y`, `n`, `a`, `q`) before removal.
- **What Gets Removed:** Only stale `dmsetup` table entries — i.e., device-mapper mappings associated with VMs that are no longer running on the host. These are **just local references** and have no impact on actual disk data.
- **Actual Disk Data Is Safe:** The underlying storage (LVM, ZFS, Ceph, etc.) is untouched. These DM entries are recreated by Proxmox when a VM is started.
- **Graceful Handling:** The script skips malformed entries, logs errors, and does not attempt unsafe operations.

#### ⚠️ Why Shutdown VMs Are Considered Stale

The script considers only **currently running VMs** (based on `qm list`) as valid for local DM entries. VMs that are powered off, migrated away, or deleted will:

- Not appear in the running list
- Be flagged if they still have active DM mappings on the host

This is intentional — device-mapper entries are only required for actively running VMs. Leaving mappings from stopped VMs serves no operational purpose and can:

- Lead to resource conflicts
- Cause “device busy” errors
- Prevent VM startup if Proxmox tries to recreate a DM entry with the same name

> Proxmox will automatically recreate DM entries on VM start, making removal of stale ones safe.

---

### Summary

This script acts as both a diagnostic tool and an optional remediation utility, offering detailed insights into the Proxmox DM state while ensuring safe and controlled cleanup operations. It is highly suitable for administrators maintaining clustered or standalone PVE nodes with complex storage mappings.

---

**End of Documentation**

