#!/bin/bash

# --- CONFIGURATION ---
BACKUP_ROOT="/run/media/aaron/flashdrive"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
BACKUP_DIR="$BACKUP_ROOT/linux_backup_$TIMESTAMP"
LOG_FILE="$BACKUP_DIR/backup_log.txt"

# --- VISUALS & UTILS ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Spinner Animation Function
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

# Wrapper to run commands with a spinner
run_task() {
    local task_name="$1"
    local command="$2"
    
    echo -n -e "${BLUE}:: $task_name...${NC} "
    eval "$command" >> "$LOG_FILE" 2>&1 &
    local pid=$!
    spinner $pid
    wait $pid
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}DONE${NC}"
    else
        echo -e "${RED}FAILED (See log)${NC}"
    fi
}

clear
echo -e "${GREEN}=== SMART SYSTEM BACKUP ===${NC}"

# 1. Drive Check
if [ ! -d "$BACKUP_ROOT" ]; then
    echo -e "${RED}Error: Flash drive not found at $BACKUP_ROOT${NC}"
    exit 1
fi

mkdir -p "$BACKUP_DIR"
touch "$LOG_FILE"

# 2. DE Detection
CURRENT_DE="Unknown"
if [[ "$XDG_CURRENT_DESKTOP" == *"GNOME"* ]]; then
    CURRENT_DE="GNOME"
elif [[ "$XDG_CURRENT_DESKTOP" == *"KDE"* ]]; then
    CURRENT_DE="KDE"
fi
echo -e "Detected Environment: ${YELLOW}$CURRENT_DE${NC}"

# 3. Size Calculation
echo -n -e "${BLUE}:: Calculating total backup size...${NC} "
# Run du in background to animate it
(du -shc "$HOME/Documents" "$HOME/Pictures" "$HOME/Videos" "$HOME/Music" "$HOME/.config" "$HOME/.mozilla" 2>/dev/null | grep total | awk '{print $1}' > /tmp/backup_size_calc) &
spinner $!
SIZE_CHECK=$(cat /tmp/backup_size_calc)
echo -e "${YELLOW}$SIZE_CHECK${NC}"

read -p "Proceed with backup? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then exit 1; fi

echo "------------------------------------------------"

# 4. The Backup Loop
run_task "Backing up Documents" "tar -czf '$BACKUP_DIR/documents.tar.gz' -C '$HOME' Documents"
run_task "Backing up Pictures"  "tar -czf '$BACKUP_DIR/pictures.tar.gz' -C '$HOME' Pictures"
run_task "Backing up Videos"    "tar -czf '$BACKUP_DIR/videos.tar.gz' -C '$HOME' Videos"
run_task "Backing up Music"     "tar -czf '$BACKUP_DIR/music.tar.gz' -C '$HOME' Music"
run_task "Backing up SSH Keys"  "tar -czf '$BACKUP_DIR/ssh_keys.tar.gz' -C '$HOME' .ssh"
run_task "Backing up GPG Keys"  "tar -czf '$BACKUP_DIR/gpg_keys.tar.gz' -C '$HOME' .gnupg"

# Configs (Excluding Cache)
run_task "Backing up User Configs (.config/.mozilla)" \
    "tar -czf '$BACKUP_DIR/user_configs.tar.gz' -C '$HOME' --exclude='.cache' .config .mozilla .local/share/fonts"

# 5. DE Specific Backup
if [ "$CURRENT_DE" == "GNOME" ]; then
    run_task "Exporting GNOME Settings (dconf)" "dconf dump / > '$BACKUP_DIR/gnome_settings.dconf'"
elif [ "$CURRENT_DE" == "KDE" ]; then
    # KDE settings are mostly in .config, which we already grabbed, but let's grab specific rc files to be safe
    run_task "Exporting KDE Specific Configs" "cp $HOME/.config/k*rc $BACKUP_DIR/ 2>/dev/null"
fi

# 6. App Lists
run_task "Exporting Flatpak List" "flatpak list --app --columns=application > '$BACKUP_DIR/flatpak_list.txt'"

echo "------------------------------------------------"
echo -e "${GREEN}Backup Complete!${NC}"
echo "Log saved to: $LOG_FILE"