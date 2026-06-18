# LK installer.

A Powershell script to install Developer menu, bootshim and LK onto your Lumia
## MAKE SURE YOU HAVE PLATFORM TOOLS AND ADB DRIVERS INSTALLED SYSTEM WIDE!

## Instructions
-   Unlock your device with WPinternals.
-   Ensure you have all the required base files in the `DATA\` directory (`BCD`, `bootshim.efi`, `Stage2.efi`, `developermenu.efi`, `emmc_appsboot.mbn`, `twrp.img`, `modem.img`). For the LineageOS installation, you must either provide `system.img`, `vendor.img`, and `boot.img` in the `DATA\` directory, OR place a LineageOS flashable zip (e.g., `lineage-18.1-*.zip`) in the script's root directory to use the ADB sideload method.
-   From WPinternals, reboot to mass storage mode (you might want to make a Win32DiskImager backup).
-   Clone this repo.
-   Run `installer.bat` as Administrator.
-   Select option `1` for a Full Install (or choose a specific phase if resuming).
-   When prompted, choose the path to the EFIESP partition (Windows might also have mounted it inside MainOS).
-   Unmount mass storage and reboot the device (keep the power key pressed).
-   The device should output some text then go to a black screen, indicating you are in LK. (Check Device Manager and install [drivers](https://developer.android.com/studio/run/win-usb) if necessary).
-   Follow the on-screen prompts in `installer.bat`—it will automatically handle booting TWRP, repartitioning, backing up partitions, flashing recovery/modem, provisioning Android partitions, and finally flashing LineageOS.
-   Once the script finishes, the device will reboot into Android!

## Included Utility Scripts

This repository includes several utility scripts to assist with ROM and firmware manipulation:
- **`unpack_ffu_to_folder.py`**: Extracts and unpacks Lumia FFU firmware files.
- **`decompress_br.py` & `sdat2img.py`**: Tools for decompressing Android system images (brotli) and converting sparse data files (`.sdat`) into raw image files.
- **`create_modem_img_70mb.bat`**: Resizes modem images to 70MB to prevent flashing issues.

## Recent Updates
- **Backup Script**: Added `backup_partitions.bat` to create comprehensive backups of all critical partitions before flashing.
- **LK Updated**: Updated `lk.bin` and `bootshim.efi` to the latest versions.
- **TWRP Updated**: Updated `twrp.img` to a version that includes `parted` for proper partitioning support.
- **Installer Improvements**:
    - **Sideload Fallback**: Added support for ADB sideloading a LineageOS flashable zip if `system.img` and `vendor.img` are not provided.
    - Improved error handling and increased timeouts for various operations.
    - Added support for new partition sizes and layout adjustments.
    - Added `adb wait-for-devices` checks to ensure the device is detected before proceeding.
