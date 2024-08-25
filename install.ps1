#Requires -RunAsAdministrator
#
# Copyright (c) Android4lumia950
#

param(
    [Parameter(Mandatory)]
    [string]$efiesp_location
)

function Get-GUID {
    param (
        $bcdeditOutput
    )

    $pattern = '(?<=\{).+?(?=\})'
    return "{$([regex]::Matches($bcdeditOutput, $pattern).Value)}"
}

Write-Output("Developer menu and bootshim installer");

$bcd_file = "$efiesp_location\EFI\Microsoft\BOOT\BCD"
$bootmgr_efis_location = "$efiesp_location\Windows\System32\BOOT"

if (-not (Test-Path -Path "$bcd_file" -PathType Leaf)) {
    Write-Output("BCD file not found")
    exit 1
}

Write-Output("Replacing BCD")
Copy-Item "$PSScriptRoot\DATA\BCD" -Destination "$bcd_file" -Force

Write-Output("Copying bootshim")
Copy-Item "$PSScriptRoot\DATA\bootshim.efi" -Destination "$bootmgr_efis_location"
Copy-Item "$PSScriptRoot\DATA\Stage2.efi" -Destination "$efiesp_location"

Write-Output("Copying developermenu")
Copy-Item -Path "$PSScriptRoot\DATA\developermenu.efi" -Destination "$bootmgr_efis_location"
New-Item -ItemType Directory -Path "$bootmgr_efis_location\ui" -Force
Copy-Item -Path "$PSScriptRoot\ui\*" -Destination "$bootmgr_efis_location\ui"

Write-Output "Copying LK2ND"
Copy-Item -Path "$PSScriptRoot\DATA\emmc_appsboot.mbn" -Destination "$efiesp_location"

Write-Output "Done! Reboot your phone and you should be prompted to LK2ND!"
Write-Host -NoNewLine 'Press any key AFTER you have rebooted into LK2ND...'
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
Write-Output("Booting TWRP");
fastboot.exe boot $PSScriptRoot\DATA\twrp.img
Write-Output("Waiting for device in recovery mode...")
adb wait-for-device
adb push ./partition.sh /
adb shell "bash ./partition.sh"
adb pull backup
adb reboot bootloader
fastboot flash recovery $PSScriptRoot\DATA\twrp.img
fastboot flash modem $PSScriptRoot\DATA\modem.img
fastboot reboot recovery
adb wait-for-device
adb push ./provision.sh /
adb shell "bash ./provision.sh"

Write-Output("Sideload an Android ROM then push any key.")
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
adb reboot

Write-Output("Booting Android...")

