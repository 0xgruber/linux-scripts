# Linux Desktop Migration Scripts 🐧📦

A set of "smart" Bash scripts designed to automate the backup and restoration of user data and configurations when migrating between Linux distributions.

These scripts were specifically engineered for migrating from **Fedora Workstation** to **Immutable/Atomic variants** (like **Bluefin**, **Aurora**, or **Bazzite**), but they are adaptable for general Linux use.

## ✨ Features

* **Smart DE Detection:** Automatically detects if you are running **GNOME** or **KDE Plasma**.
    * *GNOME:* Backs up/restores `dconf` settings (keybindings, theme, mouse settings).
    * *KDE:* Backs up/restores `.config` files.
    * *Safety:* Prevents applying GNOME settings onto a KDE desktop (and vice-versa) during restore.
* **Full User Data:** Backs up `Documents`, `Pictures`, `Videos`, `Music`, `SSH Keys`, and `GPG Keys`.
* **Flatpak Migration:** Exports a list of installed Flatpaks and automatically re-installs them on the new system.
* **SELinux Aware:** Automatically runs `restorecon` on restored files (critical for Fedora/Bluefin/RHEL to prevent permission errors).
* **Space Safety:** Calculates total backup size and prompts for confirmation before starting.
* **Visual Feedback:** Includes a spinner animation so you know the script is working during long file transfers.

---

## 🚀 Quick Start

### 1. The Backup (Run on Source Machine)

1.  Mount your external drive (Flash drive / SSD).
2.  Open `backup_smart.sh` and edit the **Configuration** section to match your drive path:
    ```bash
    BACKUP_ROOT="/run/media/yourusername/flashdrive"
    ```
3.  Make the script executable and run it:
    ```bash
    chmod +x backup_smart.sh
    ./backup_smart.sh
    ```
    *This will create a timestamped folder on your drive (e.g., `linux_backup_2024-11-25_14-30`).*

### 2. The Restore (Run on Target Machine)

1.  Boot into your new OS (Bluefin, Aurora, etc.).
2.  Connect your external drive.
3.  Open `restore_smart.sh` and **UPDATE the backup folder name**:
    ```bash
    # You MUST change this to match the folder created by the backup script
    BACKUP_FOLDER_NAME="linux_backup_2024-11-25_14-30"
    ```
4.  Make executable and run:
    ```bash
    chmod +x restore_smart.sh
    ./restore_smart.sh
    ```
5.  **Reboot your computer** to ensure all settings and groups are applied correctly.

---

## ⚙️ Configuration Details

Both scripts have a configuration block at the top.

| Variable | Description |
| :--- | :--- |
| `BACKUP_ROOT` | The path to your USB drive. On Fedora/Arch, this is usually `/run/media/user/drive`. On Ubuntu, it is usually `/media/user/drive`. |
| `BACKUP_FOLDER_NAME` | **(Restore Script Only)** The specific folder name generated during the backup process. You must copy/paste this manually to ensure you are restoring the correct snapshot. |

### What gets backed up?
* `~/Documents`, `~/Pictures`, `~/Videos`, `~/Music`
* `~/.ssh` and `~/.gnupg` (Permissions preserved)
* `~/.config`, `~/.mozilla` (Firefox profiles), `~/.local/share/fonts`
* **GNOME:** `dconf` database dump.
* **KDE:** `.config` rc files.

### What is EXCLUDED?
* `~/.cache` (To save space)
* `~/Downloads` (Usually temporary/junk)
* System-wide packages (RPMs/DEBs) are **not** backed up. Only the list of Flatpaks is preserved.

---

## ⚠️ Compatibility Notes

### Fedora / Bluefin / Aurora / RHEL
These scripts are optimized for these distros. They utilize `restorecon` to fix SELinux contexts after files are moved. This is critical for immutable desktops.

### Ubuntu / Debian / Mint
If you are running these scripts on Debian-based systems:
1.  **Mount Paths:** Check your `BACKUP_ROOT` path (usually `/media` not `/run/media`).
2.  **SELinux:** These systems use AppArmor, not SELinux. The script attempts to run `restorecon`, but will simply fail that specific step gracefully (or you can remove that line).

---

## 📄 Logs
The scripts generate log files for troubleshooting.
* **Backup:** Saves `backup_log.txt` inside the backup folder on the USB drive.
* **Restore:** Saves `restore_log.txt` in your Home directory.

## ⚖️ Disclaimer
**Always verify your backups.** While these scripts are designed to be safe, moving data always carries risk. The author is not responsible for data loss. Ensure your `BACKUP_ROOT` is correct before running.