@echo off
:: ============================================================
::  LineageOS 18.1 Installer for Microsoft Lumia 950 XL (Cityman)
:: ============================================================
::
::  This script automates the installation of LineageOS 18.1
::  on the Microsoft Lumia 950 XL (codename: Cityman).
::
::  Overview of the installation process:
::    1. Patch the EFIESP partition with a custom BCD,
::       bootshim, Stage2 UEFI loader, developermenu,
::       and LK2ND (Little Kernel 2nd-stage bootloader)
::    2. Boot into TWRP recovery via fastboot
::    3. Repartition the eMMC storage for dual-boot
::    4. Backup existing partitions (timestamped)
::    5. Flash TWRP recovery and modem firmware
::    6. Provision the Android partition layout
::    7. Flash LineageOS system/vendor imgs (or ADB sideload zip)
::
::  Requirements:
::    - Windows 10/11 with admin privileges
::    - Lumia 950 XL connected via USB
::    - EFIESP partition accessible (Mass Storage Mode)
::    - All required files in the DATA\ directory
::
::  Required files:
::    DATA\BCD               - Custom Boot Configuration Data
::    DATA\bootshim.efi      - UEFI boot shim
::    DATA\Stage2.efi        - Stage 2 UEFI loader
::    DATA\developermenu.efi - Developer menu UEFI app
::    DATA\emmc_appsboot.mbn - LK2ND bootloader
::    DATA\twrp.img          - TWRP recovery image
::    DATA\modem.img         - Modem firmware
::    DATA\PLAT.img          - Boot logo partition image (FAT12)
::    DATA\system.img        - LineageOS system image (Optional if sideloading zip)
::    DATA\vendor.img        - LineageOS vendor image (Optional if sideloading zip)
::    DATA\boot.img          - LineageOS boot image (Optional if sideloading zip)
::    lineage-18.1-*.zip     - Flashable zip in script dir (Fallback if imgs are missing)
::    partition.sh           - eMMC repartition script
::    provision.sh           - Android partition provisioning
::    ui\*                   - Developer menu UI assets
::    bin\adb.exe            - Android Debug Bridge
::    bin\fastboot.exe       - Fastboot utility
::
:: ============================================================

:: Check for admin privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting administrative privileges...
    PowerShell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

setlocal EnableDelayedExpansion

REM ============================================================
REM  Setup log file
REM ============================================================
for /f %%i in ('PowerShell -NoProfile -Command "Get-Date -Format ''dd.MM.yyyy_HHmm''"') do set "log_date=%%i"
set "LOGFILE=%~dp0install_log_%log_date%.txt"
echo ============================================ > "%LOGFILE%"
echo  LineageOS 18.1 Installer - Lumia 950 XL >> "%LOGFILE%"
echo  Log started: %log_date% >> "%LOGFILE%"
echo ============================================ >> "%LOGFILE%"
echo. >> "%LOGFILE%"

echo.
echo  ============================================================
echo   LineageOS 18.1 Installer for Lumia 950 XL (Cityman)
echo  ============================================================
echo   Log file: %LOGFILE%
echo.

REM ============================================================
REM  Phase selection menu
REM ============================================================
echo  Select where to start:
echo.
echo    1. Full install (start from the beginning)
echo    2. Phone is already in TWRP (skip EFIESP + fastboot boot)
echo    3. Repartition done, continue from backup + flash
echo    4. Phone is in bootloader, flash recovery + modem
echo    5. Recovery + modem flashed, run provisioning
echo    6. Provisioning done, flash LineageOS images only
echo    7. Rescue bootloop via Mass Storage Mode (Flash boot/recovery)
echo.
set /p "start_phase=  Enter choice (1-7): "

if "!start_phase!"=="7" goto phase7_rescue

REM ============================================================
REM  Pre-flight checks: verify all required files exist
REM ============================================================
echo [*] Running pre-flight checks...
echo [INFO] Running pre-flight checks >> "%LOGFILE%"
set "preflight_ok=1"

set "use_sideload=0"
set "sideload_zip="
if not exist "%~dp0DATA\system.img" if not exist "%~dp0DATA\vendor.img" (
    for %%Z in ("%~dp0lineage-18.1*.zip") do (
        set "use_sideload=1"
        set "sideload_zip=%%Z"
    )
)

REM -- Required DATA files --
set "data_files=BCD bootshim.efi Stage2.efi developermenu.efi emmc_appsboot.mbn twrp.img modem.img PLAT.img"
if "!use_sideload!"=="0" (
    set "data_files=!data_files! boot.img system.img vendor.img"
) else (
    echo [INFO] system.img and vendor.img not found, but LineageOS zip found. Will use adb sideload.
    echo [INFO] LineageOS zip found for sideload: !sideload_zip! >> "%LOGFILE%"
)

for %%F in (!data_files!) do (
    if not exist "%~dp0DATA\%%F" (
        echo  [ERROR] MISSING: DATA\%%F
        echo [ERROR] MISSING: DATA\%%F >> "%LOGFILE%"
        set "preflight_ok=0"
    )
)

REM -- Required scripts --
for %%F in (partition.sh provision.sh) do (
    if not exist "%~dp0%%F" (
        echo  [ERROR] MISSING: %%F
        echo [ERROR] MISSING: %%F >> "%LOGFILE%"
        set "preflight_ok=0"
    )
)

REM -- Required tools --
for %%F in (adb.exe fastboot.exe) do (
    if not exist "%~dp0bin\%%F" (
        echo  [ERROR] MISSING: bin\%%F
        echo [ERROR] MISSING: bin\%%F >> "%LOGFILE%"
        set "preflight_ok=0"
    )
)

REM -- UI directory --
if not exist "%~dp0ui\" (
    echo  [ERROR] MISSING: ui\ directory
    echo [ERROR] MISSING: ui\ directory >> "%LOGFILE%"
    set "preflight_ok=0"
)

if "!preflight_ok!"=="0" (
    echo.
    echo  [!!] Pre-flight check FAILED. Missing files listed above.
    echo       Please make sure all required files are present and try again.
    echo [ERROR] Pre-flight check FAILED - aborting >> "%LOGFILE%"
    pause
    exit /b 1
)
echo [OK] All required files found.
echo [INFO] Pre-flight check passed >> "%LOGFILE%"
echo.

if "!start_phase!"=="2" goto phase2_adb
if "!start_phase!"=="3" goto phase3_backup
if "!start_phase!"=="4" goto phase4_flash
if "!start_phase!"=="5" goto phase5_provision
if "!start_phase!"=="6" goto phase6_lineageos

REM ============================================================
REM  PHASE 1: Patch EFIESP partition
REM ============================================================
echo  --- PHASE 1: Patch EFIESP partition ---
echo.

:: Prompt for EFIESP directory
set "psCommand="(new-object -COM 'Shell.Application')^
.BrowseForFolder(0,'Select EFIESP directory.',0,0).self.path""

for /f "usebackq delims=" %%I in (`powershell %psCommand%`) do set "efiesp_location=%%I"

if not defined efiesp_location (
    echo  [ERROR] No EFIESP directory selected. Aborting.
    echo [ERROR] No EFIESP directory selected >> "%LOGFILE%"
    pause
    exit /b 1
)
echo [INFO] EFIESP directory: %efiesp_location% >> "%LOGFILE%"

REM Define paths
set "bcd_file=%efiesp_location%\EFI\Microsoft\BOOT\BCD"
set "bootmgr_efisp_location=%efiesp_location%\Windows\System32\BOOT"

REM Check if BCD file exists on the device
IF NOT EXIST "%bcd_file%" (
    echo  [ERROR] BCD file not found at %bcd_file% - make sure it's the right path
    echo [ERROR] BCD not found at %bcd_file% >> "%LOGFILE%"
    pause
    exit /b 1
)

:: Confirmation before modifying EFIESP
echo.
echo  [WARNING] This will overwrite the BCD and UEFI boot files
echo            on the EFIESP partition at: %efiesp_location%
echo.
set /p "confirm_efiesp=  Are you sure you want to continue? (Y/N): "
if /i "!confirm_efiesp!" NEQ "Y" (
    echo Operation cancelled by user.
    exit /b 0
)

echo Replacing BCD
copy /y "%~dp0DATA\BCD" "%bcd_file%" >> "%LOGFILE%" 2>&1
IF ERRORLEVEL 1 (
    echo  [ERROR] Failed to copy BCD to %bcd_file%
    echo [ERROR] Failed to copy BCD >> "%LOGFILE%"
    pause
    exit /b 1
)

echo Copying bootshim
copy /y "%~dp0DATA\bootshim.efi" "%bootmgr_efisp_location%" >> "%LOGFILE%" 2>&1
IF ERRORLEVEL 1 (
    echo  [ERROR] Failed to copy bootshim.efi
    echo [ERROR] Failed to copy bootshim.efi >> "%LOGFILE%"
    pause
    exit /b 1
)

copy /y "%~dp0DATA\Stage2.efi" "%efiesp_location%" >> "%LOGFILE%" 2>&1
IF ERRORLEVEL 1 (
    echo  [ERROR] Failed to copy Stage2.efi
    echo [ERROR] Failed to copy Stage2.efi >> "%LOGFILE%"
    pause
    exit /b 1
)

echo Copying developermenu
copy /y "%~dp0DATA\developermenu.efi" "%bootmgr_efisp_location%" >> "%LOGFILE%" 2>&1
IF ERRORLEVEL 1 (
    echo  [ERROR] Failed to copy developermenu.efi
    echo [ERROR] Failed to copy developermenu.efi >> "%LOGFILE%"
    pause
    exit /b 1
)

if not exist "%bootmgr_efisp_location%\ui" (
    md "%bootmgr_efisp_location%\ui" >> "%LOGFILE%" 2>&1
    IF ERRORLEVEL 1 (
        echo  [ERROR] Failed to create ui directory
        echo [ERROR] Failed to create ui directory >> "%LOGFILE%"
        pause
    exit /b 1
    )
)
copy /y "%~dp0ui\*" "%bootmgr_efisp_location%\ui\" >> "%LOGFILE%" 2>&1
IF ERRORLEVEL 1 (
    echo  [ERROR] Failed to copy ui files
    echo [ERROR] Failed to copy ui files >> "%LOGFILE%"
    pause
    exit /b 1
)

echo Copying LK2ND
copy /y "%~dp0DATA\emmc_appsboot.mbn" "%efiesp_location%" >> "%LOGFILE%" 2>&1
IF ERRORLEVEL 1 (
    echo  [ERROR] Failed to copy emmc_appsboot.mbn
    echo [ERROR] Failed to copy emmc_appsboot.mbn >> "%LOGFILE%"
    echo  [INFO] Please check "%LOGFILE%" for more details.
    pause
    exit /b 1
)

echo.
echo [OK] EFIESP patching complete!

REM Removed Phase 1.5: PLAT partition is FAT12 and hard to mount on Windows.
REM Instead, PLAT.img will be flashed via fastboot in Phase 2.

echo.
echo     Reboot your phone and you should be prompted to LK2ND.
echo     Press any key when ready to continue to Phase 2...
echo [INFO] EFIESP patching complete >> "%LOGFILE%"
pause

REM ============================================================
REM  PHASE 2: Boot TWRP and repartition
REM ============================================================
echo.
echo  --- PHASE 2: Boot TWRP recovery and repartition ---
echo.


echo Booting recovery via fastboot
%~dp0bin\fastboot boot "%~dp0DATA\twrp.img"
IF ERRORLEVEL 1 (
    echo  [ERROR] Failed to fastboot boot twrp.img
    echo [ERROR] Failed to fastboot boot twrp.img >> "%LOGFILE%"
    pause
    exit /b 1
)
echo [INFO] Fastboot boot twrp.img sent >> "%LOGFILE%"
goto waitforadb

:phase2_adb
REM Entry point when phone is already in TWRP
echo.
echo  --- PHASE 2: Connect to TWRP and repartition ---
echo.

:waitforadb
echo Waiting for device in recovery mode...
echo Make sure your Lumia 950 XL is connected via USB.
timeout /t 10 /nobreak
for /f "tokens=1" %%i in ('%~dp0bin\adb devices') do (
    if "%%i" NEQ "List" (
        if "%%i" NEQ "" (
            if "%%i" NEQ "*" (
                echo [OK] ADB device connected: %%i
                echo [INFO] ADB device connected: %%i >> "%LOGFILE%"
                goto insiderecovery
            )
        )
    )
)
echo   Device not found yet, retrying...
goto waitforadb

:insiderecovery

if exist "%~dp0DATA\PLAT.img" (
    echo Flashing PLAT.img Boot Logo via TWRP...
    %~dp0bin\adb push "%~dp0DATA\PLAT.img" /tmp/PLAT.img >> "%LOGFILE%" 2>&1
    IF ERRORLEVEL 1 (
        echo  [WARNING] Failed to push PLAT.img to TWRP.
        echo [WARNING] Failed to push PLAT.img >> "%LOGFILE%"
    ) ELSE (
        %~dp0bin\adb shell "if [ -e /dev/block/bootdevice/by-name/PLAT ]; then dd if=/tmp/PLAT.img of=/dev/block/bootdevice/by-name/PLAT; elif [ -e /dev/block/bootdevice/by-name/plat ]; then dd if=/tmp/PLAT.img of=/dev/block/bootdevice/by-name/plat; else exit 1; fi" >> "%LOGFILE%" 2>&1
        IF ERRORLEVEL 1 (
            echo  [WARNING] Failed to flash PLAT.img. Partition not found in TWRP.
            echo [WARNING] Failed to flash PLAT.img via dd >> "%LOGFILE%"
        ) ELSE (
            echo [OK] Boot logo PLAT.img flashed successfully!
            echo [INFO] Flashed PLAT.img via dd >> "%LOGFILE%"
        )
    )
)

:: Confirmation before destructive partitioning
echo.
echo  [WARNING] The next step will REPARTITION the eMMC storage.
echo            This is a DESTRUCTIVE operation. Existing data on
echo            the Android partitions will be erased.
echo            A backup will be taken before flashing.
echo.
set /p "confirm_partition=  Continue with repartitioning? (Y/N): "
if /i "!confirm_partition!" NEQ "Y" (
    echo Operation cancelled by user.
    exit /b 0
)

echo Copying partition script
%~dp0bin\adb push "%~dp0partition.sh" / >nul 2>&1
IF ERRORLEVEL 1 (
    echo  [ERROR] Failed to push partition.sh to device
    echo  [!!] Make sure the device is still in TWRP recovery.
    echo [ERROR] Failed to push partition.sh >> "%LOGFILE%"
    pause
    exit /b 1
)
echo [INFO] partition.sh pushed >> "%LOGFILE%"

echo Running partition script (this may take a moment)...
%~dp0bin\adb shell "bash /partition.sh"
IF ERRORLEVEL 1 (
    echo  [ERROR] Failed to run partition.sh on device
    echo  [!!] Check the device screen for any error messages.
    echo [ERROR] Failed to run partition.sh >> "%LOGFILE%"
    pause
    exit /b 1
)
echo [INFO] partition.sh executed successfully >> "%LOGFILE%"

REM ============================================================
REM  PHASE 3: Backup existing partitions
REM ============================================================
:phase3_backup
echo.
echo  --- PHASE 3: Backup existing partitions ---
echo.

for /f %%i in ('PowerShell -NoProfile -Command "Get-Date -Format ''dd.MM.yyyy_HHmm''"') do set "current_date=-%%i"

rem Create the backup folder with the current date
set "backup_folder=backup%current_date%"

echo Pulling backup from device...
%~dp0bin\adb pull /backup %~dp0 >nul 2>&1
IF ERRORLEVEL 1 (
    echo  [WARNING] Could not pull backup from device (this is not critical)
    echo [WARNING] Failed to pull backup >> "%LOGFILE%"
    goto skip_backup
)
PowerShell -Command "mv '%~dp0backup' '%backup_folder%' " >nul 2>&1
IF ERRORLEVEL 1 (
    echo  [WARNING] Could not rename backup folder (this is not critical)
    echo [WARNING] Failed to rename backup folder >> "%LOGFILE%"
    goto skip_backup
)
echo [OK] Backup saved to: %backup_folder%
echo [INFO] Backup saved to %backup_folder% >> "%LOGFILE%"
:skip_backup

REM ============================================================
REM  PHASE 4: Flash recovery and modem
REM ============================================================
:phase4_flash
echo.
echo  --- PHASE 4: Flash recovery and modem ---
echo.

echo Rebooting to bootloader
%~dp0bin\adb reboot bootloader

echo.
echo Waiting for device in fastboot/bootloader mode...
echo If this takes too long, check that:
echo   - LK2ND is showing on the phone screen
echo   - Fastboot USB drivers are installed (Google USB Driver or WPInternals)
echo   - USB cable is connected
echo.

:waitfb1
%~dp0bin\fastboot devices 2>nul | findstr /R /C:"fastboot" >nul 2>&1
IF ERRORLEVEL 1 (
    echo   Fastboot device not found, retrying in 5 seconds...
    timeout /t 5 /nobreak >nul
    goto waitfb1
)
echo [OK] Fastboot device detected!
echo [INFO] Fastboot device detected for Phase 4 >> "%LOGFILE%"

echo Flashing recovery (TWRP)
%~dp0bin\fastboot flash recovery "%~dp0DATA\twrp.img"
echo [INFO] Recovery flash command sent >> "%LOGFILE%"

echo Flashing modem
%~dp0bin\fastboot flash modem "%~dp0DATA\modem.img"
echo [INFO] Modem flash command sent >> "%LOGFILE%"

echo Rebooting to recovery
%~dp0bin\fastboot reboot recovery

echo.
echo Press any key when the device is in recovery...
pause

REM ============================================================
REM  PHASE 5: Provision Android partitions
REM ============================================================
:phase5_provision
echo.
echo  --- PHASE 5: Provision Android partitions ---
echo.

echo Waiting for device in ADB mode...
:waitforadb2
timeout /t 5 /nobreak >nul
for /f "tokens=1" %%i in ('%~dp0bin\adb devices') do (
    if "%%i" NEQ "List" (
        if "%%i" NEQ "" (
            if "%%i" NEQ "*" (
                echo [OK] ADB device connected: %%i
                echo [INFO] ADB device connected for Phase 5: %%i >> "%LOGFILE%"
                goto adb2_ready
            )
        )
    )
)
echo   Device not found yet, retrying...
goto waitforadb2
:adb2_ready

echo Copying provisioning script
%~dp0bin\adb push "%~dp0provision.sh" / >nul 2>&1
IF ERRORLEVEL 1 (
    echo  [ERROR] Failed to push provision.sh to device
    echo [ERROR] Failed to push provision.sh >> "%LOGFILE%"
    pause
    exit /b 1
)
echo [INFO] provision.sh pushed >> "%LOGFILE%"

echo Running provisioning script
%~dp0bin\adb shell "bash /provision.sh"
IF ERRORLEVEL 1 (
    echo  [ERROR] Failed to run provision.sh on device
    echo [ERROR] Failed to run provision.sh >> "%LOGFILE%"
    pause
    exit /b 1
)
echo [INFO] provision.sh executed successfully >> "%LOGFILE%"

REM ============================================================
REM  PHASE 6: Flash LineageOS system and vendor images
REM ============================================================
:phase6_lineageos
echo.
echo  --- PHASE 6: Flash LineageOS 18.1 images ---
echo.

:: Confirmation before flashing OS images
if "!use_sideload!"=="1" (
    echo  [WARNING] This will sideload LineageOS 18.1 zip
    echo            to the device. This is irreversible.
) else (
    echo  [WARNING] This will flash LineageOS 18.1 system, vendor, and boot
    echo            images to the device. This is irreversible.
)
echo.
set /p "confirm_flash=  Continue with flashing LineageOS? (Y/N): "
if /i "!confirm_flash!" NEQ "Y" (
    echo Operation cancelled by user.
    exit /b 0
)

if "!use_sideload!"=="1" (
    echo.
    set "sideload_found=0"
    for /f "tokens=2" %%i in ('%~dp0bin\adb devices') do (
        if "%%i"=="sideload" set "sideload_found=1"
    )
    if "!sideload_found!"=="1" (
        echo Device is already in sideload mode.
    ) else (
        echo Starting TWRP sideload mode...
        %~dp0bin\adb shell twrp sideload >nul 2>&1
        
        echo.
        echo Waiting for device to enter sideload mode...
        :waitsideload
        timeout /t 5 /nobreak >nul
        set "sideload_found=0"
        for /f "tokens=2" %%i in ('%~dp0bin\adb devices') do (
            if "%%i"=="sideload" set "sideload_found=1"
        )
        if "!sideload_found!"=="0" (
            echo   Device not in sideload mode yet.
            echo   If it's stuck, please manually start ADB Sideload from TWRP Advanced menu!
            goto waitsideload
        )
        echo [OK] Device is in sideload mode!
    )

    echo Sideloading LineageOS zip ^(this will take a while^)...
    %~dp0bin\adb sideload "!sideload_zip!"
    echo [INFO] Sideloaded !sideload_zip! >> "%LOGFILE%"
    
) else (
    echo Rebooting to bootloader for flashing system/vendor...
    %~dp0bin\adb reboot bootloader

    echo.
    echo Waiting for device in fastboot/bootloader mode...
    echo.

    :waitfb2
    %~dp0bin\fastboot devices 2>nul | findstr /R /C:"fastboot" >nul 2>&1
    IF ERRORLEVEL 1 (
        echo   Fastboot device not found, retrying in 5 seconds...
        timeout /t 5 /nobreak >nul
        goto waitfb2
    )
    echo [OK] Fastboot device detected!
    echo [INFO] Fastboot device detected for Phase 6 >> "%LOGFILE%"

    echo Flashing system.img ^(this may take a while^)...
    %~dp0bin\fastboot flash system "%~dp0DATA\system.img"
    echo [INFO] system.img flash command sent >> "%LOGFILE%"

    echo Flashing vendor.img...
    %~dp0bin\fastboot flash vendor "%~dp0DATA\vendor.img"
    echo [INFO] vendor.img flash command sent >> "%LOGFILE%"

    echo Flashing boot.img...
    %~dp0bin\fastboot flash boot "%~dp0DATA\boot.img"
    echo [INFO] boot.img flash command sent >> "%LOGFILE%"
)

echo Rebooting device
%~dp0bin\adb reboot 
goto done_installation

REM ============================================================
REM  PHASE 7: Rescue Bootloop (Mass Storage Mode)
REM ============================================================
:phase7_rescue
echo.
echo  --- PHASE 7: Rescue Bootloop (Mass Storage Mode) ---
echo.
echo  Instructions:
echo  1. Force reboot your Lumia (Hold Power + Vol Down for 10s until vibration).
echo  2. As soon as it vibrates, hold the Camera button (or Vol Up on some UIs).
echo  3. Select "Mass Storage Mode" in the Developer Menu.
echo  4. Connect the phone to your PC via USB.
echo.
echo  What do you want to flash to rescue the device?
echo    1. TWRP Recovery (Flash twrp.img to boot partition) [Recommended]
echo    2. LineageOS Boot (Flash boot.img to boot partition)
echo.
set /p "rescue_choice=  Enter choice (1-2): "

set "rescue_img="
if "!rescue_choice!"=="1" set "rescue_img=twrp.img"
if "!rescue_choice!"=="2" set "rescue_img=boot.img"

if "!rescue_img!"=="" (
    echo Invalid choice.
    pause
    exit /b 1
)

echo.
echo Launching PowerShell rescue script...
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0rescue.ps1" -ImageName "!rescue_img!" -PartitionName "boot"

echo.
echo Rescue operation finished. Check the PowerShell window for success/failure.
pause
exit /b 0

:done_installation

REM ============================================================
REM  Done!
REM ============================================================
echo [INFO] Installation completed successfully >> "%LOGFILE%"
echo.
echo  ============================================================
echo   Installation complete!
echo   LineageOS 18.1 has been installed on your Lumia 950 XL.
echo   The device is now rebooting.
echo.
echo   Log saved to: %LOGFILE%
echo  ============================================================
pause
exit /b 0
