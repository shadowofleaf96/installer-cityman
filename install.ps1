#Requires -RunAsAdministrator
#
# Copyright (c) Android4Lumia950
#
# Define the warning message
$warningMessage = @"
********************************************************************************
                            WARNING: READ THIS CAREFULLY
********************************************************************************

Your warranty is now void. We are not responsible for bricked devices, dead SD cards,
thermonuclear war, or you getting fired because the alarm app failed. Please, do some
research if you have any concerns about the features included in these ROMs before
flashing anything. YOU are choosing to make these modifications on your own, and if
you point the finger at us for messing up your device, we will laugh at you.

********************************************************************************
"@

# Display the warning message
Write-Host $warningMessage -ForegroundColor Red;

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
Write-Output("Make sure you have made a backup either with Win32DiskImager OR with WPInternals!")
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
# Copy-Item "$PSScriptRoot\Stage2.efi" -Destination "$efiesp_location"

Write-Output("Copying developermenu")
Copy-Item -Path "$PSScriptRoot\developermenu.efi" -Destination "$bootmgr_efis_location"
New-Item -ItemType Directory -Path "$bootmgr_efis_location\ui" -Force
Copy-Item -Path "$PSScriptRoot\ui\*" -Destination "$bootmgr_efis_location\ui"

Write-Output("Copying LK2ND")
Copy-Item -Path "$PSScriptRoot\DATA\emmc_appsboot.mbn" -Destination "$efiesp_location"

Write-Output("Done! Reboot your phone and you should be prompted to LK2ND!");
Write-Host -NoNewLine 'Press any key AFTER you have rebooted into LK2ND...';
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
Write-Output("Booting TWRP");
./fastboot.exe boot $PSScriptRoot\DATA\twrp.img
adb push ./partition.sh /
adb shell "bash ./partition.sh"
adb pull backup
adb reboot bootloader
./fastboot.exe flash recovery $PSScriptRoot\DATA\twrp.img
fastboot reboot recovery