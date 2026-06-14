@echo off
:: Check for Administrator privileges
net session >nul 2>&1
if %errorLevel% == 0 (
    goto :admin
) else (
    echo Requesting Administrator privileges to use ImDisk...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:admin
echo ========================================================
echo   Creating EXACTLY 70MB modem.img for fastboot
echo ========================================================
echo.

set "IMG_FILE=%~dp0modem.img"
set "SRC_DIR=%~dp0modem_firmware"
set "MOUNT_LETTER=M:"

:: Clean up old mount if it got stuck
imdisk -d -m %MOUNT_LETTER% >nul 2>&1

:: Delete old file if it exists
if exist "%IMG_FILE%" del "%IMG_FILE%"

echo [1] Creating a 70MB virtual disk image (matches 73400320 bytes)...
:: Using /fs:fat to use FAT16 since FAT32 has too much overhead for 68MB of files in a 70MB partition.
imdisk -a -s 70M -m %MOUNT_LETTER% -f "%IMG_FILE%" -p "/fs:fat /q /y"

echo.
echo [2] Copying modem firmware files into the FAT image...
xcopy /s /e /y "%SRC_DIR%\*" "%MOUNT_LETTER%\"

echo.
echo [3] Unmounting the virtual disk and saving changes...
imdisk -d -m %MOUNT_LETTER%

echo.
echo ========================================================
echo   Done! Your 70MB flashable modem.img has been created!
echo   %IMG_FILE%
echo ========================================================
pause
