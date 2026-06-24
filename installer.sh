#!/bin/bash

# ============================================================
#  LineageOS 18.1 Installer for Microsoft Lumia 950 XL (Cityman)
# ============================================================
#
#  This script automates the installation of LineageOS 18.1
#  on the Microsoft Lumia 950 XL (codename: Cityman).
#
#  Overview of the installation process:
#    1. Patch the EFIESP partition with a custom BCD,
#       bootshim, Stage2 UEFI loader, developermenu,
#       and LK2ND (Little Kernel 2nd-stage bootloader)
#    2. Boot into TWRP recovery via fastboot
#    3. Repartition the eMMC storage for dual-boot
#    4. Backup existing partitions (timestamped)
#    5. Flash TWRP recovery and modem firmware
#    6. Provision the Android partition layout
#    7. Flash LineageOS system/vendor imgs (or ADB sideload zip)
#
#  Requirements:
#    - Ubuntu 24.04 (or other Linux) with root privileges
#    - adb and fastboot installed
#    - Lumia 950 XL connected via USB
#    - EFIESP partition mounted and accessible
#    - All required files in the DATA/ directory
#
# ============================================================

# Check for root/sudo
if [ "$EUID" -ne 0 ]; then
    echo "Requesting administrative privileges..."
    exec sudo "$0" "$@"
    exit $?
fi

BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# ============================================================
#  Setup log file
# ============================================================
LOG_DATE=$(date +"%d.%m.%Y_%H%M")
LOGFILE="${BASE_DIR}/install_log_${LOG_DATE}.txt"

echo "============================================" > "$LOGFILE"
echo " LineageOS 18.1 Installer - Lumia 950 XL" >> "$LOGFILE"
echo " Log started: $LOG_DATE" >> "$LOGFILE"
echo "============================================" >> "$LOGFILE"
echo "" >> "$LOGFILE"

echo ""
echo " ============================================================"
echo "  LineageOS 18.1 Installer for Lumia 950 XL (Cityman)"
echo " ============================================================"
echo "  Log file: $LOGFILE"
echo ""

# Find ADB and FASTBOOT
ADB="adb"
FASTBOOT="fastboot"

if [ -x "${BASE_DIR}/bin/adb" ]; then
    ADB="${BASE_DIR}/bin/adb"
fi
if [ -x "${BASE_DIR}/bin/fastboot" ]; then
    FASTBOOT="${BASE_DIR}/bin/fastboot"
fi

# ============================================================
#  Pre-flight checks: verify all required files exist
# ============================================================
echo "[*] Running pre-flight checks..."
echo "[INFO] Running pre-flight checks" >> "$LOGFILE"
preflight_ok=1

use_sideload=0
sideload_zip=""

if [ ! -f "${BASE_DIR}/DATA/system.img" ] && [ ! -f "${BASE_DIR}/DATA/vendor.img" ]; then
    for z in "${BASE_DIR}"/lineage-18.1*.zip; do
        if [ -f "$z" ]; then
            use_sideload=1
            sideload_zip="$z"
            break
        fi
    done
fi

# -- Required DATA files --
data_files=("BCD" "bootshim.efi" "Stage2.efi" "developermenu.efi" "emmc_appsboot.mbn" "twrp.img" "modem.img" "PLAT.img")
if [ "$use_sideload" -eq 0 ]; then
    data_files+=("boot.img" "system.img" "vendor.img")
else
    echo "[INFO] system.img and vendor.img not found, but LineageOS zip found. Will use adb sideload."
    echo "[INFO] LineageOS zip found for sideload: $sideload_zip" >> "$LOGFILE"
fi

for f in "${data_files[@]}"; do
    if [ ! -f "${BASE_DIR}/DATA/$f" ]; then
        echo " [ERROR] MISSING: DATA/$f"
        echo "[ERROR] MISSING: DATA/$f" >> "$LOGFILE"
        preflight_ok=0
    fi
done

# -- Required scripts --
for f in "partition.sh" "provision.sh"; do
    if [ ! -f "${BASE_DIR}/$f" ]; then
        echo " [ERROR] MISSING: $f"
        echo "[ERROR] MISSING: $f" >> "$LOGFILE"
        preflight_ok=0
    fi
done

# -- Required tools --
if ! command -v $ADB >/dev/null 2>&1; then
    echo " [ERROR] adb is missing. Please install it (e.g., sudo apt install adb) or place it in bin/"
    echo "[ERROR] adb missing" >> "$LOGFILE"
    preflight_ok=0
fi

if ! command -v $FASTBOOT >/dev/null 2>&1; then
    echo " [ERROR] fastboot is missing. Please install it (e.g., sudo apt install fastboot) or place it in bin/"
    echo "[ERROR] fastboot missing" >> "$LOGFILE"
    preflight_ok=0
fi

# -- UI directory --
if [ ! -d "${BASE_DIR}/ui" ]; then
    echo " [ERROR] MISSING: ui/ directory"
    echo "[ERROR] MISSING: ui/ directory" >> "$LOGFILE"
    preflight_ok=0
fi

if [ "$preflight_ok" -eq 0 ]; then
    echo ""
    echo " [!!] Pre-flight check FAILED. Missing files/tools listed above."
    echo "      Please make sure all required files are present and try again."
    echo "[ERROR] Pre-flight check FAILED - aborting" >> "$LOGFILE"
    read -p "Press Enter to exit..."
    exit 1
fi

echo "[OK] All required files found."
echo "[INFO] Pre-flight check passed" >> "$LOGFILE"
echo ""

# ============================================================
#  Phase selection menu
# ============================================================
echo " Select where to start:"
echo ""
echo "   1. Full install (start from the beginning)"
echo "   2. Phone is already in TWRP (skip EFIESP + fastboot boot)"
echo "   3. Repartition done, continue from backup + flash"
echo "   4. Phone is in bootloader, flash recovery + modem"
echo "   5. Recovery + modem flashed, run provisioning"
echo "   6. Provisioning done, flash LineageOS images only"
echo "   7. Rescue bootloop via Mass Storage Mode (Flash boot/recovery)"
echo ""
read -p "  Enter choice (1-7): " start_phase

# ============================================================
#  Phases
# ============================================================

phase1_efiesp() {
    echo ""
    echo " --- PHASE 1: Patch EFIESP partition ---"
    echo ""
    
    # Try to use a GUI folder picker if available, otherwise fallback to terminal input
    if command -v zenity >/dev/null 2>&1 && [ -n "$DISPLAY" ]; then
        efiesp_location=$(zenity --file-selection --directory --title="Select mounted EFIESP directory")
    else
        read -p "Enter path to mounted EFIESP directory: " efiesp_location
    fi

    if [ -z "$efiesp_location" ] || [ ! -d "$efiesp_location" ]; then
        echo " [ERROR] No valid EFIESP directory selected. Aborting."
        echo "[ERROR] No EFIESP directory selected" >> "$LOGFILE"
        exit 1
    fi
    echo "[INFO] EFIESP directory: $efiesp_location" >> "$LOGFILE"

    bcd_file="$efiesp_location/EFI/Microsoft/BOOT/BCD"
    bootmgr_efisp_location="$efiesp_location/Windows/System32/BOOT"

    if [ ! -f "$bcd_file" ]; then
        echo " [ERROR] BCD file not found at $bcd_file - make sure it's the right path"
        echo "[ERROR] BCD not found at $bcd_file" >> "$LOGFILE"
        exit 1
    fi

    echo ""
    echo " [WARNING] This will overwrite the BCD and UEFI boot files"
    echo "           on the EFIESP partition at: $efiesp_location"
    echo ""
    read -p "  Are you sure you want to continue? (Y/N): " confirm_efiesp
    if [[ ! "$confirm_efiesp" =~ ^[Yy]$ ]]; then
        echo "Operation cancelled by user."
        exit 0
    fi

    echo "Replacing BCD"
    if ! cp -f "${BASE_DIR}/DATA/BCD" "$bcd_file"; then
        echo " [ERROR] Failed to copy BCD to $bcd_file"
        echo "[ERROR] Failed to copy BCD" >> "$LOGFILE"
        exit 1
    fi

    echo "Copying bootshim"
    if ! cp -f "${BASE_DIR}/DATA/bootshim.efi" "$bootmgr_efisp_location"; then
        echo " [ERROR] Failed to copy bootshim.efi"
        echo "[ERROR] Failed to copy bootshim.efi" >> "$LOGFILE"
        exit 1
    fi

    if ! cp -f "${BASE_DIR}/DATA/Stage2.efi" "$efiesp_location"; then
        echo " [ERROR] Failed to copy Stage2.efi"
        echo "[ERROR] Failed to copy Stage2.efi" >> "$LOGFILE"
        exit 1
    fi

    echo "Copying developermenu"
    if ! cp -f "${BASE_DIR}/DATA/developermenu.efi" "$bootmgr_efisp_location"; then
        echo " [ERROR] Failed to copy developermenu.efi"
        echo "[ERROR] Failed to copy developermenu.efi" >> "$LOGFILE"
        exit 1
    fi

    if [ ! -d "$bootmgr_efisp_location/ui" ]; then
        if ! mkdir -p "$bootmgr_efisp_location/ui"; then
            echo " [ERROR] Failed to create ui directory"
            echo "[ERROR] Failed to create ui directory" >> "$LOGFILE"
            exit 1
        fi
    fi

    if ! cp -f "${BASE_DIR}"/ui/* "$bootmgr_efisp_location/ui/"; then
        echo " [ERROR] Failed to copy ui files"
        echo "[ERROR] Failed to copy ui files" >> "$LOGFILE"
        exit 1
    fi

    echo "Copying LK2ND"
    if ! cp -f "${BASE_DIR}/DATA/emmc_appsboot.mbn" "$efiesp_location"; then
        echo " [ERROR] Failed to copy emmc_appsboot.mbn"
        echo "[ERROR] Failed to copy emmc_appsboot.mbn" >> "$LOGFILE"
        exit 1
    fi

    echo ""
    echo "[OK] EFIESP patching complete!"

    echo ""
    echo "    Reboot your phone and you should be prompted to LK2ND."
    echo "    Press Enter when ready to continue to Phase 2..."
    echo "[INFO] EFIESP patching complete" >> "$LOGFILE"
    read -r
}

phase2_twrp() {
    echo ""
    echo " --- PHASE 2: Boot TWRP recovery and repartition ---"
    echo ""
    echo "Booting recovery via fastboot"
    if ! $FASTBOOT boot "${BASE_DIR}/DATA/twrp.img"; then
        echo " [ERROR] Failed to fastboot boot twrp.img"
        echo "[ERROR] Failed to fastboot boot twrp.img" >> "$LOGFILE"
        exit 1
    fi
    echo "[INFO] Fastboot boot twrp.img sent" >> "$LOGFILE"
    waitforadb
}

phase2_adb() {
    echo ""
    echo " --- PHASE 2: Connect to TWRP and repartition ---"
    echo ""
    waitforadb
}

waitforadb() {
    echo "Waiting for device in recovery mode..."
    echo "Make sure your Lumia 950 XL is connected via USB."
    sleep 10
    
    while true; do
        dev=$($ADB devices | grep -v "List" | grep -v "^$" | head -n 1 | awk '{print $1}')
        if [ -n "$dev" ] && [ "$dev" != "*" ] && [ "$dev" != "offline" ] && [ "$dev" != "unauthorized" ]; then
            echo "[OK] ADB device connected: $dev"
            echo "[INFO] ADB device connected: $dev" >> "$LOGFILE"
            break
        fi
        echo "  Device not found yet, retrying in 5s..."
        sleep 5
    done
    insiderecovery
}

insiderecovery() {
    if [ -f "${BASE_DIR}/DATA/PLAT.img" ]; then
        echo "Flashing PLAT.img Boot Logo via TWRP..."
        if ! $ADB push "${BASE_DIR}/DATA/PLAT.img" /tmp/PLAT.img >> "$LOGFILE" 2>&1; then
            echo " [WARNING] Failed to push PLAT.img to TWRP."
            echo "[WARNING] Failed to push PLAT.img" >> "$LOGFILE"
        else
            if ! $ADB shell "if [ -e /dev/block/bootdevice/by-name/PLAT ]; then dd if=/tmp/PLAT.img of=/dev/block/bootdevice/by-name/PLAT; elif [ -e /dev/block/bootdevice/by-name/plat ]; then dd if=/tmp/PLAT.img of=/dev/block/bootdevice/by-name/plat; else exit 1; fi" >> "$LOGFILE" 2>&1; then
                echo " [WARNING] Failed to flash PLAT.img. Partition not found in TWRP."
                echo "[WARNING] Failed to flash PLAT.img via dd" >> "$LOGFILE"
            else
                echo "[OK] Boot logo PLAT.img flashed successfully!"
                echo "[INFO] Flashed PLAT.img via dd" >> "$LOGFILE"
            fi
        fi
    fi

    echo ""
    echo " [WARNING] The next step will REPARTITION the eMMC storage."
    echo "           This is a DESTRUCTIVE operation. Existing data on"
    echo "           the Android partitions will be erased."
    echo "           A backup will be taken before flashing."
    echo ""
    read -p "  Continue with repartitioning? (Y/N): " confirm_partition
    if [[ ! "$confirm_partition" =~ ^[Yy]$ ]]; then
        echo "Operation cancelled by user."
        exit 0
    fi

    echo "Copying partition script"
    if ! $ADB push "${BASE_DIR}/partition.sh" / >/dev/null 2>&1; then
        echo " [ERROR] Failed to push partition.sh to device"
        echo " [!!] Make sure the device is still in TWRP recovery."
        echo "[ERROR] Failed to push partition.sh" >> "$LOGFILE"
        exit 1
    fi
    echo "[INFO] partition.sh pushed" >> "$LOGFILE"

    echo "Running partition script (this may take a moment)..."
    if ! $ADB shell "bash /partition.sh"; then
        echo " [ERROR] Failed to run partition.sh on device"
        echo " [!!] Check the device screen for any error messages."
        echo "[ERROR] Failed to run partition.sh" >> "$LOGFILE"
        exit 1
    fi
    echo "[INFO] partition.sh executed successfully" >> "$LOGFILE"
}

phase3_backup() {
    echo ""
    echo " --- PHASE 3: Backup existing partitions ---"
    echo ""
    current_date=$(date +"%d.%m.%Y_%H%M")
    backup_folder="backup-${current_date}"

    echo "Pulling backup from device..."
    if ! $ADB pull /backup "${BASE_DIR}" >/dev/null 2>&1; then
        echo " [WARNING] Could not pull backup from device (this is not critical)"
        echo "[WARNING] Failed to pull backup" >> "$LOGFILE"
    else
        if ! mv "${BASE_DIR}/backup" "${BASE_DIR}/${backup_folder}" >/dev/null 2>&1; then
            echo " [WARNING] Could not rename backup folder (this is not critical)"
            echo "[WARNING] Failed to rename backup folder" >> "$LOGFILE"
        else
            echo "[OK] Backup saved to: $backup_folder"
            echo "[INFO] Backup saved to $backup_folder" >> "$LOGFILE"
        fi
    fi
}

phase4_flash() {
    echo ""
    echo " --- PHASE 4: Flash recovery and modem ---"
    echo ""
    echo "Rebooting to bootloader"
    $ADB reboot bootloader
    
    echo ""
    echo "Waiting for device in fastboot/bootloader mode..."
    echo "If this takes too long, check that:"
    echo "  - LK2ND is showing on the phone screen"
    echo "  - USB cable is connected"
    echo ""
    
    while true; do
        if $FASTBOOT devices 2>/dev/null | grep -q "fastboot"; then
            break
        fi
        echo "  Fastboot device not found, retrying in 5 seconds..."
        sleep 5
    done
    
    echo "[OK] Fastboot device detected!"
    echo "[INFO] Fastboot device detected for Phase 4" >> "$LOGFILE"

    echo "Flashing recovery (TWRP)"
    $FASTBOOT flash recovery "${BASE_DIR}/DATA/twrp.img"
    echo "[INFO] Recovery flash command sent" >> "$LOGFILE"

    echo "Flashing modem"
    $FASTBOOT flash modem "${BASE_DIR}/DATA/modem.img"
    echo "[INFO] Modem flash command sent" >> "$LOGFILE"

    echo "Rebooting to recovery"
    $FASTBOOT reboot recovery

    echo ""
    read -p "Press Enter when the device is in recovery..."
}

phase5_provision() {
    echo ""
    echo " --- PHASE 5: Provision Android partitions ---"
    echo ""
    echo "Waiting for device in ADB mode..."
    sleep 5
    
    while true; do
        dev=$($ADB devices | grep -v "List" | grep -v "^$" | head -n 1 | awk '{print $1}')
        if [ -n "$dev" ] && [ "$dev" != "*" ] && [ "$dev" != "offline" ] && [ "$dev" != "unauthorized" ]; then
            echo "[OK] ADB device connected: $dev"
            echo "[INFO] ADB device connected for Phase 5: $dev" >> "$LOGFILE"
            break
        fi
        echo "  Device not found yet, retrying in 5s..."
        sleep 5
    done
    
    echo "Copying provisioning script"
    if ! $ADB push "${BASE_DIR}/provision.sh" / >/dev/null 2>&1; then
        echo " [ERROR] Failed to push provision.sh to device"
        echo "[ERROR] Failed to push provision.sh" >> "$LOGFILE"
        exit 1
    fi
    echo "[INFO] provision.sh pushed" >> "$LOGFILE"

    echo "Running provisioning script"
    if ! $ADB shell "bash /provision.sh"; then
        echo " [ERROR] Failed to run provision.sh on device"
        echo "[ERROR] Failed to run provision.sh" >> "$LOGFILE"
        exit 1
    fi
    echo "[INFO] provision.sh executed successfully" >> "$LOGFILE"
}

phase6_lineageos() {
    echo ""
    echo " --- PHASE 6: Flash LineageOS 18.1 images ---"
    echo ""

    if [ "$use_sideload" -eq 1 ]; then
        echo " [WARNING] This will sideload LineageOS 18.1 zip"
        echo "           to the device. This is irreversible."
    else
        echo " [WARNING] This will flash LineageOS 18.1 system, vendor, and boot"
        echo "           images to the device. This is irreversible."
    fi
    echo ""
    read -p "  Continue with flashing LineageOS? (Y/N): " confirm_flash
    if [[ ! "$confirm_flash" =~ ^[Yy]$ ]]; then
        echo "Operation cancelled by user."
        exit 0
    fi

    if [ "$use_sideload" -eq 1 ]; then
        echo ""
        sideload_found=0
        if $ADB devices | grep -q "sideload"; then
            sideload_found=1
        fi
        
        if [ "$sideload_found" -eq 1 ]; then
            echo "Device is already in sideload mode."
        else
            echo "Starting TWRP sideload mode..."
            $ADB shell twrp sideload >/dev/null 2>&1
            
            echo ""
            echo "Waiting for device to enter sideload mode..."
            while true; do
                sleep 5
                if $ADB devices | grep -q "sideload"; then
                    break
                fi
                echo "  Device not in sideload mode yet."
                echo "  If it's stuck, please manually start ADB Sideload from TWRP Advanced menu!"
            done
            echo "[OK] Device is in sideload mode!"
        fi

        echo "Sideloading LineageOS zip (this will take a while)..."
        $ADB sideload "$sideload_zip"
        echo "[INFO] Sideloaded $sideload_zip" >> "$LOGFILE"

        echo "Rebooting device"
        $ADB reboot
    else
        echo "Rebooting to bootloader for flashing"
        $ADB reboot bootloader

        echo ""
        echo "Waiting for device in fastboot/bootloader mode..."
        echo ""

        while true; do
            if $FASTBOOT devices 2>/dev/null | grep -q "fastboot"; then
                break
            fi
            echo "  Fastboot device not found, retrying in 5 seconds..."
            sleep 5
        done
        
        echo "[OK] Fastboot device detected!"
        echo "[INFO] Fastboot device detected for Phase 6" >> "$LOGFILE"

        echo "Flashing system.img (this may take a while)..."
        $FASTBOOT flash system "${BASE_DIR}/DATA/system.img"
        echo "[INFO] system.img flash command sent" >> "$LOGFILE"

        echo "Flashing vendor.img..."
        $FASTBOOT flash vendor "${BASE_DIR}/DATA/vendor.img"
        echo "[INFO] vendor.img flash command sent" >> "$LOGFILE"

        echo "Flashing boot.img..."
        $FASTBOOT flash boot "${BASE_DIR}/DATA/boot.img"
        echo "[INFO] boot.img flash command sent" >> "$LOGFILE"

        echo "Rebooting device"
        $FASTBOOT reboot
    fi
}

phase7_rescue() {
    echo ""
    echo " --- PHASE 7: Rescue Bootloop (Mass Storage Mode) ---"
    echo ""
    echo " Instructions:"
    echo " 1. Force reboot your Lumia (Hold Power + Volume Down for 10s until vibration)."
    echo " 2. As soon as it vibrates, hold the Camera button (or Vol Up on some UIs)."
    echo " 3. Select \"Mass Storage Mode\" in the Developer Menu."
    echo " 4. Connect the phone to your PC via USB."
    echo ""
    echo " What do you want to flash to rescue the device?"
    echo "   1. TWRP Recovery (Flash twrp.img to boot partition) [Recommended]"
    echo "   2. LineageOS Boot (Flash boot.img to boot partition)"
    echo ""
    read -p "  Enter choice (1-2): " rescue_choice

    rescue_img=""
    if [ "$rescue_choice" == "1" ]; then rescue_img="twrp.img"; fi
    if [ "$rescue_choice" == "2" ]; then rescue_img="boot.img"; fi

    if [ -z "$rescue_img" ]; then
        echo "Invalid choice."
        exit 1
    fi

    echo ""
    echo "Launching bash rescue script..."
    bash "${BASE_DIR}/rescue.sh" "$rescue_img" "boot"

    echo ""
    echo "Rescue operation finished. Check the output above for success/failure."
    exit 0
}

# ============================================================
#  Execution Flow based on Phase
# ============================================================
case "$start_phase" in
    1|"")
        phase1_efiesp
        phase2_twrp
        phase3_backup
        phase4_flash
        phase5_provision
        phase6_lineageos
        ;;
    2)
        phase2_adb
        phase3_backup
        phase4_flash
        phase5_provision
        phase6_lineageos
        ;;
    3)
        phase3_backup
        phase4_flash
        phase5_provision
        phase6_lineageos
        ;;
    4)
        phase4_flash
        phase5_provision
        phase6_lineageos
        ;;
    5)
        phase5_provision
        phase6_lineageos
        ;;
    6)
        phase6_lineageos
        ;;
    7)
        phase7_rescue
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo "[INFO] Installation completed successfully" >> "$LOGFILE"
echo ""
echo " ============================================================"
echo "  Installation complete!"
echo "  LineageOS 18.1 has been installed on your Lumia 950 XL."
echo "  The device is now rebooting."
echo ""
echo "  Log saved to: $LOGFILE"
echo " ============================================================"
read -p "Press Enter to exit..."
exit 0
