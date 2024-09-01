@echo off
REM Requires Administrator Privileges

REM Check if the first argument (efiesp_location) is provided
IF "%~1"=="" (
    echo Usage: %0 ^<efiesp_location^>
    exit /b 1
)

set "efiesp_location=%~1"

REM Define paths
set "bcd_file=%efiesp_location%\EFI\Microsoft\BOOT\BCD"
set "bootmgr_efis_location=%efiesp_location%\Windows\System32\BOOT"

REM Check if BCD file exists
IF NOT EXIST "%bcd_file%" (
    echo BCD file not found at %bcd_file%
    exit /b 1
)

echo Replacing BCD
copy /y "%~dp0DATA\BCD" "%bcd_file%" >nul 2>&1
IF ERRORLEVEL 1 (
    echo Failed to copy BCD file
    exit /b 1
)

echo Copying bootshim
copy /y "%~dp0DATA\bootshim.efi" "%bootmgr_efis_location%" >nul 2>&1
IF ERRORLEVEL 1 (
    echo Failed to copy bootshim.efi
    exit /b 1
)
copy /y "%~dp0DATA\Stage2.efi" "%efiesp_location%" >nul 2>&1
IF ERRORLEVEL 1 (
    echo Failed to copy Stage2.efi
    exit /b 1
)

echo Copying developermenu
copy /y "%~dp0DATA\developermenu.efi" "%bootmgr_efis_location%" >nul 2>&1
IF ERRORLEVEL 1 (
    echo Failed to copy developermenu.efi
    exit /b 1
)
if not exist "%bootmgr_efis_location%\ui" (
    md "%bootmgr_efis_location%\ui" >nul 2>&1
    IF ERRORLEVEL 1 (
        echo Failed to create ui directory
        exit /b 1
    )
)
copy /y "%~dp0ui\*" "%bootmgr_efis_location%\ui\" >nul 2>&1
IF ERRORLEVEL 1 (
    echo Failed to copy ui files
    exit /b 1
)

echo Copying LK2ND
copy /y "%~dp0DATA\emmc_appsboot.mbn" "%efiesp_location%" >nul 2>&1
IF ERRORLEVEL 1 (
    echo Failed to copy emmc_appsboot.mbn
    exit /b 1
)

echo Done! Reboot your phone and you should be prompted to LK2ND!
pause

echo Booting TWRP

REM Check if fastboot.exe is available
where fastboot.exe >nul 2>&1 || (
    echo fastboot.exe not found in PATH
    exit /b 1
)

fastboot boot "%~dp0DATA\twrp.img"
IF ERRORLEVEL 1 (
    echo Failed to boot TWRP
    exit /b 1
)

echo Waiting for device in recovery mode...
adb wait-for-device
IF ERRORLEVEL 1 (
    echo Failed to detect device
    exit /b 1
)

echo Copying partition script
adb push "%~dp0partition.sh" / >nul 2>&1
IF ERRORLEVEL 1 (
    echo Failed to push partition.sh
    exit /b 1
)

echo Running partition script
adb shell "bash /partition.sh"
IF ERRORLEVEL 1 (
    echo Failed to run partition.sh
    exit /b 1
)

echo Pulling backup
adb pull /backup >nul 2>&1
IF ERRORLEVEL 1 (
    echo Failed to pull backup
    exit /b 1
)

echo Rebooting to bootloader
adb reboot bootloader
IF ERRORLEVEL 1 (
    echo Failed to reboot to bootloader
    exit /b 1
)

REM Flashing recovery and modem images
fastboot flash recovery "%~dp0DATA\twrp.img"
IF ERRORLEVEL 1 (
    echo Failed to flash recovery image
    exit /b 1
)
fastboot flash modem "%~dp0DATA\modem.img"
IF ERRORLEVEL 1 (
    echo Failed to flash modem image
    exit /b 1
)

echo Rebooting to recovery
fastboot reboot recovery
IF ERRORLEVEL 1 (
    echo Failed to reboot to recovery
    exit /b 1
)

adb wait-for-device
IF ERRORLEVEL 1 (
    echo Failed to detect device in recovery mode
    exit /b 1
)

echo Copying provisioning script
adb push "%~dp0provision.sh" / >nul 2>&1
IF ERRORLEVEL 1 (
    echo Failed to push provision.sh
    exit /b 1
)

echo Running provisioning script
adb shell "bash /provision.sh"
IF ERRORLEVEL 1 (
    echo Failed to run provision.sh
    exit /b 1
)

echo Sideload an Android ROM then press any key.
pause

adb reboot
IF ERRORLEVEL 1 (
    echo Failed to reboot device
    exit /b 1
)

echo Booting Android...
