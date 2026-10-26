# LK Installer for Microsoft Lumia 950 XL (Cityman)

Automated scripts (Windows Batch and Linux Bash) to install Developer Menu, bootshim, LK2ND (Little Kernel), and LineageOS 18.1 onto your Microsoft Lumia 950 XL.

> [!IMPORTANT]
> Make sure you have Android SDK Platform-Tools and ADB/Fastboot drivers installed system-wide!

---

## Instructions

1. **Unlock Device**: Unlock your Lumia bootloader using [WPInternals](https://www.wpinternals.net/).
2. **Prepare Files**: Ensure you have all required base files in the `DATA\` directory:
   - `BCD`, `bootshim.efi`, `Stage2.efi`, `developermenu.efi`, `emmc_appsboot.mbn` (LK2ND)
   - `twrp.img` (Updated TWRP recovery with latest kernel)
   - `modem.img` (70MB modem firmware partition image)
   - `PLAT.img` (Optional: Custom boot logo partition image) or `logo1.png`
   - **ROM Files**: Either provide `system.img`, `vendor.img`, and `boot.img` in `DATA\`, **OR** place a LineageOS flashable zip (e.g., `lineage-18.1-*.zip`) in the root directory for automatic ADB sideloading.
3. **Reboot to Mass Storage Mode**:
   - Force reboot your phone (Hold **Power + Volume Down** for ~10 seconds until it vibrates).
   - Immediately press and hold the **Camera** button (or **Volume Up** on some builds) to enter the Developer Menu.
   - Select **Mass Storage Mode** and connect the phone to your PC via USB *(making a raw eMMC backup with Win32DiskImager or `dd` is strongly recommended)*.
4. **Run the Installer**:
   - **Windows**: Right-click `installer.bat` and select **Run as Administrator**.
   - **Linux**: Make executable and run `installer.sh` (`chmod +x installer.sh && ./installer.sh`).
5. **Select Phase**: Choose option `1` for a Full Install (or choose a specific phase to resume).
6. **Patch EFIESP**: When prompted, select the mounted `EFIESP` partition directory.
7. **Reboot to LK2ND**: Unmount mass storage and force reboot the phone (hold Power + Vol Down). The screen will display LK text and proceed to LK2ND / TWRP.
8. **Automated Steps**: The installer will automatically:
   - Boot TWRP recovery via fastboot.
   - Flash the custom boot logo (`PLAT.img`).
   - Repartition the eMMC storage (including the 384MiB `vendor` partition).
   - Backup critical partitions (timestamped in `backup/`).
   - Flash TWRP recovery, modem firmware, and provision Android partitions.
   - Flash LineageOS images or ADB sideload the ROM zip.
9. **Finish**: Once the process completes, the phone reboots straight into LineageOS!

---

## Bootloop Rescue (Mass Storage Mode)

If your device is stuck in a bootloop, black screen, or fails to boot into fastboot/recovery, use the built-in Mass Storage rescue utility:

- **Windows (`rescue.ps1` / Option 7 in `installer.bat`)**:
  1. Force reboot into the Developer Menu (Hold Power + Vol Down, then hold Camera button on vibration).
  2. Select **Mass Storage Mode** and connect to your PC.
  3. Select option `7` in `installer.bat` (or run `rescue.ps1` in an elevated PowerShell).
  4. The script identifies the physical USB disk, parses the GPT partition table in raw mode, and safely writes `twrp.img` or `boot.img` directly to the `boot` or `recovery` partition.
- **Linux (`rescue.sh` / Option 7 in `installer.sh`)**:
  - Run `sudo ./rescue.sh <image_name> <partition_name>` (e.g., `sudo ./rescue.sh twrp.img boot`).

---

## Included Utility Scripts

This repository includes several utility scripts to assist with ROM manipulation, rescue, and firmware building:

- **`rescue.ps1` & `rescue.sh`**: Direct physical disk GPT parser and partition flasher for Mass Storage Mode rescue (Windows & Linux).
- **`create_modem_img_70mb.bat` & `create_modem_img.sh`**: Scripts (Windows & Linux) to create and format a 70MB FAT16 modem partition image populated with firmware blobs.
- **`pil-splitter.py`**: Splits Qualcomm ELF firmware files into `*.mdt` headers and `*.b<n>` segments for the modem image.
- **`unpack_ffu_to_folder.py`**: Extracts and unpacks Lumia FFU firmware files.
- **`decompress_br.py` & `sdat2img.py`**: Tools for decompressing Android system images (brotli) and converting sparse data files (`.sdat`) into raw image files.

---

## Recent Updates

- **TWRP Recovery Kernel Updated**: Updated `DATA/twrp.img` with a newer kernel for enhanced stability, hardware support, and proper partitioning.
- **Boot & Modem Images Updated**: Synchronized `DATA/boot.img` and `DATA/modem.img` with the latest kernel and firmware fixes.
- **Vendor Partition Resized**: Increased the `vendor` partition from 260MiB to 384MiB in `partition.sh` to accommodate modern vendor builds without out-of-space errors.
- **Bootloop Rescue Utility**: Added `rescue.ps1` (PowerShell) and `rescue.sh` (Bash), accessible directly via Phase 7 in the installers, to revive bricked devices from Mass Storage Mode.
- **Custom Boot Logo (PLAT Partition)**: Added automated flashing of `PLAT.img` via TWRP in `installer.bat` and `installer.sh` to safely update the boot logo without Windows FAT12 mount issues.
- **Cross-Platform Linux Support**: Full Linux Bash equivalents provided (`installer.sh`, `rescue.sh`, and `create_modem_img.sh`).
- **Installer Reliability Improvements**:
  - Added user pauses on errors so error details are visible instead of closing the terminal.
  - Comprehensive logging redirected to timestamped `install_log_*.txt` files.
  - Added Mass Storage Mode hardware key instructions in Phase 1.
  - Added `adb wait-for-devices` verification checks before executing critical recovery phases.
  - Automatic fallback ADB sideloading for LineageOS flashable zip.
