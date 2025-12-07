#!/bin/bash

# --- CONFIGURATION ---
# USER MUST EDIT THIS
BACKUP_FOLDER_NAME="linux_backup_YYYY-MM-DD_HH-MM"
BACKUP_SOURCE="/run/media/aaron/flashdrive/$BACKUP_FOLDER_NAME"
LOG_FILE="$HOME/restore_log.txt"

# --- VISUALS ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ -d /proc/$pid ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

run_task() {
    local task_name="$1"
    local command="$2"
    echo -n -e "${BLUE}:: $task_name...${NC} "
    eval "$command" >> "$LOG_FILE" 2>&1 &
    spinner $!
    echo -e "${GREEN}DONE${NC}"
}

clear
echo -e "${GREEN}=== SMART SYSTEM RESTORE ===${NC}"

if [[ "$BACKUP_FOLDER_NAME" == *"YYYY-MM-DD"* ]]; then
    echo -e "${RED}WAIT! You need to edit the script to set the BACKUP_FOLDER_NAME.${NC}"
    exit 1
fi

if [ ! -d "$BACKUP_SOURCE" ]; then
    echo -e "${RED}Error: Backup folder not found at $BACKUP_SOURCE${NC}"
    exit 1
fi

# 1. DE Detection
CURRENT_DE="Unknown"
if [[ "$XDG_CURRENT_DESKTOP" == *"GNOME"* ]]; then
    CURRENT_DE="GNOME"
elif [[ "$XDG_CURRENT_DESKTOP" == *"KDE"* ]]; then
    CURRENT_DE="KDE"
fi
echo -e "Target Environment: ${YELLOW}$CURRENT_DE${NC}"
echo "Restoring from: $BACKUP_SOURCE"
read -p "Start restore? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then exit 1; fi

# 2. Restore Files
run_task "Restoring Documents" "tar -xzf '$BACKUP_SOURCE/documents.tar.gz' -C '$HOME'"
run_task "Restoring Pictures"  "tar -xzf '$BACKUP_SOURCE/pictures.tar.gz' -C '$HOME'"
run_task "Restoring Videos"    "tar -xzf '$BACKUP_SOURCE/videos.tar.gz' -C '$HOME'"
run_task "Restoring Music"     "tar -xzf '$BACKUP_SOURCE/music.tar.gz' -C '$HOME'"
run_task "Restoring SSH Keys"  "tar -xzf '$BACKUP_SOURCE/ssh_keys.tar.gz' -C '$HOME'"
run_task "Restoring GPG Keys"  "tar -xzf '$BACKUP_SOURCE/gpg_keys.tar.gz' -C '$HOME'"
run_task "Restoring Configs"   "tar -xzf '$BACKUP_SOURCE/user_configs.tar.gz' -C '$HOME'"

# 3. Smart DE Settings Restore
if [ "$CURRENT_DE" == "GNOME" ]; then
    if [ -f "$BACKUP_SOURCE/gnome_settings.dconf" ]; then
        run_task "Applying GNOME Settings" "dconf load / < '$BACKUP_SOURCE/gnome_settings.dconf'"
    else
        echo -e "${YELLOW}:: Skipping GNOME settings (Not found in backup)${NC}"
    fi
elif [ "$CURRENT_DE" == "KDE" ]; then
    echo -e "${YELLOW}:: KDE Detected - Configs were restored via .config folder.${NC}"
fi

# 4. Flatpak Reinstall
if [ -f "$BACKUP_SOURCE/flatpak_list.txt" ]; then
    echo -n -e "${BLUE}:: Reinstalling Flatpaks (This takes time)...${NC} "
    # We don't use the spinner here because we want to see the flatpak progress output usually, 
    # but for a script we will hide it and log it.
    (xargs -a "$BACKUP_SOURCE/flatpak_list.txt" flatpak install -y flathub >> "$LOG_FILE" 2>&1) &
    spinner $!
    echo -e "${GREEN}DONE${NC}"
fi

# 5. Fix Permissions
run_task "Fixing SELinux Permissions" "restorecon -Rv '$HOME'"

echo "------------------------------------------------"
echo -e "${GREEN}Restore Complete! Reboot is highly recommended.${NC}"