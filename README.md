# LK installer.

A Powershell script to install Developer menu, bootshim and LK onto your Lumia
## MAKE SURE YOU HAVE PLATFORM TOOLS AND ADB DRIVERS INSTALLED SYSTEM WIDE!

## Instructions
-   Unlock your device with WPinternals
-   From WPinternals, reboot to mass storage mode (you might want to make a Win32DiskImager backup)
-   Clone this repo
-   Run install.bat
-   Choose the path to EFIESP (Windows might also have mounted it inside MainOS)
-   Unmount mass storage
-   Reboot the device (keep pressed power key)
-   Device should output some print stuff then go into a black screen, you SHOULD be in LK by that point.(check device manager and install [drivers](https://developer.android.com/studio/run/win-usb))
-   The script will boot you in TWRP, make the partitions needed for android and back up your provisioned partitions.
-   You will reboot to the bootloader after this process is done, it will flash TWRP and reboot to it again.
-   Then you will have to sideload the LOS rom of your choice (for now only 18.1 is available).
-   Then continue with the script, it will reboot you to the bootloader to flash the kernel, (WIP: and modem) then boot you in android.
-   Enjoy!