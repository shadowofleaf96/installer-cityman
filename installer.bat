@echo off
:: Check for admin privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting administrative privileges...
    :: Relaunch the batch file with admin rights
    PowerShell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
::Prompt for EFIESP directory
setlocal

set "psCommand="(new-object -COM 'Shell.Application')^
.BrowseForFolder(0,'Select EFIESP directory.',0,0).self.path""

for /f "usebackq delims=" %%I in (`powershell %psCommand%`) do set "efiesp_location=%%I"

REM Define paths
set "bcd_file=%efiesp_location%\EFI\Microsoft\BOOT\BCD"
set "bootmgr_efisp_location=%efiesp_location%\Windows\System32\BOOT"

REM Check if BCD file exists
IF NOT EXIST "%bcd_file%" (
    echo "BCD file not found at %bcd_file% make sure it's the right path"
    exit /b 1
)

echo Replacing BCD
copy /y "%~dp0DATA\BCD" "%bcd_file%" >nul 2>&1

echo Copying bootshim
copy /y "%~dp0DATA\bootshim.efi" "%bootmgr_efisp_location%" >nul 2>&1

copy /y "%~dp0DATA\Stage2.efi" "%efiesp_location%" >nul 2>&1


echo Copying developermenu
copy /y "%~dp0DATA\developermenu.efi" "%bootmgr_efisp_location%" >nul 2>&1

if not exist "%bootmgr_efisp_location%\ui" (
    md "%bootmgr_efisp_location%\ui" >nul 2>&1
    IF ERRORLEVEL 1 (
        echo Failed to create ui directory
        exit /b 1
    )
)
copy /y "%~dp0ui\*" "%bootmgr_efisp_location%\ui\" >nul 2>&1


echo Copying LK2ND
copy /y "%~dp0DATA\emmc_appsboot.mbn" "%efiesp_location%" >nul 2>&1

echo Done! Reboot your phone and you should be prompted to LK2ND!
pause

echo Booting recovery

%~dp0bin\fastboot boot "%~dp0DATA\twrp.img"

:waitforadb
echo Waiting for device in recovery mode...
timeout /t 15 /nobreak
for /f "tokens=1" %%i in ('%~dp0bin\adb devices') do (
    if "%%i" NEQ "List" (
        if "%%i" NEQ "" (
            echo ADB device connected: %%i
            goto insiderecovery
        )
    )
)
goto waitforadb

:insiderecovery
echo Copying partition script
%~dp0bin\adb push "%~dp0partition.sh" / >nul 2>&1
IF ERRORLEVEL 1 (
    echo Failed to push partition.sh
    exit /b 1
)

echo Running partition script
%~dp0bin\adb shell "bash /partition.sh"
IF ERRORLEVEL 1 (
    echo Failed to run partition.sh
    exit /b 1
)

for /f "tokens=2 delims==" %%i in ('wmic os get localdatetime /value ^| find "="') do set datetime=%%i
set "current_date=-%datetime:~6,2%.%datetime:~4,2%.%datetime:~0,4%_%datetime:~8,4%"

rem Create the backup folder with the current date
set "backup_folder=backup%current_date%"

echo Pulling backup
%~dp0bin\adb pull /backup %~dp0 >nul 2>&1
PowerShell -Command "mv '%~dp0backup' '%backup_folder%' "

echo Rebooting to bootloader
%~dp0bin\adb reboot bootloader

REM Flashing recovery and modem images
%~dp0bin\fastboot flash recovery "%~dp0DATA\twrp.img"

%~dp0bin\fastboot flash modem "%~dp0DATA\modem.img"

echo Rebooting to recovery
%~dp0bin\fastboot reboot recovery

echo Press any key when in recovery...
pause


echo Copying provisioning script
%~dp0bin\adb push "%~dp0provision.sh" / >nul 2>&1

echo Running provisioning script
%~dp0bin\adb shell "bash /provision.sh"

echo Sideload an Android ROM then press any key.
pause

%~dp0bin\adb reboot

echo Booting Android...
