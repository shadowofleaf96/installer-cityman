<#
.SYNOPSIS
    Rescues a Lumia 950 XL from a bootloop by directly writing to the Android boot/recovery
    partitions via USB Mass Storage Mode.
.DESCRIPTION
    This script identifies USB physical disks, parses their GPT structure to find the
    exact byte offset of a named Android partition (e.g. "boot", "recovery"), and raw-writes 
    the provided image file directly to the device.
#>

param (
    [string]$ImageName = "twrp.img",
    [string]$PartitionName = "boot"
)

# Request elevation if not running as Admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Administrator privileges are required to write to physical disks. Elevating..."
    $arguments = "& '" + $myinvocation.mycommand.definition + "' -ImageName '$ImageName' -PartitionName '$PartitionName'"
    Start-Process powershell -Verb runAs -ArgumentList $arguments
    break
}

Write-Host "============================================================"
Write-Host "  Lumia 950 XL Bootloop Rescue (Mass Storage Mode)"
Write-Host "============================================================"
Write-Host ""
Write-Host "Target Image     : DATA\$ImageName"
Write-Host "Target Partition : $PartitionName"
Write-Host ""

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$imagePath = Join-Path $scriptPath "DATA\$ImageName"

if (-not (Test-Path $imagePath)) {
    Write-Error "Could not find image at: $imagePath"
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Scanning for USB Physical Disks..."
# Find USB drives, filter out the system drive to be safe
$disks = Get-Disk | Where-Object { $_.BusType -eq 'USB' -and $_.IsSystem -eq $false -and $_.IsBoot -eq $false }

if (-not $disks) {
    Write-Error "No USB Physical Disks found! Ensure your phone is in Mass Storage Mode and connected."
    Read-Host "Press Enter to exit"
    exit 1
}

$targetDisk = $null
if ($disks.Count -gt 1) {
    Write-Host "Multiple USB disks found. Please select your Lumia device:"
    for ($i = 0; $i -lt $disks.Count; $i++) {
        Write-Host "  [$i] Disk $($disks[$i].Number): $($disks[$i].Model) ($([math]::Round($disks[$i].Size / 1GB, 2)) GB)"
    }
    $choice = Read-Host "Enter disk number [0-$($disks.Count - 1)]"
    $targetDisk = $disks[[int]$choice]
} else {
    $targetDisk = $disks[0]
    Write-Host "Found USB Disk $($targetDisk.Number): $($targetDisk.Model) ($([math]::Round($targetDisk.Size / 1GB, 2)) GB)"
}

if (-not $targetDisk) {
    Write-Error "Invalid disk selection."
    exit 1
}

$diskNum = $targetDisk.Number
$diskPath = "\\.\PhysicalDrive$diskNum"

Write-Host ""
Write-Host "[WARNING] About to read partition table from Disk $diskNum ($diskPath)"
Write-Host "Taking disk offline to bypass Windows volume protection..."
Write-Host ""

try {
    Set-Disk -Number $diskNum -IsOffline $true
    Start-Sleep -Seconds 1
    Set-Disk -Number $diskNum -IsReadOnly $false
    Start-Sleep -Seconds 1
    $stream = [System.IO.File]::Open($diskPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite)
} catch {
    Write-Error "Failed to open physical drive. Ensure no other tool (like Disk Management) is locking the drive."
    Write-Error $_.Exception.Message
    Read-Host "Press Enter to exit"
    try { Set-Disk -Number $diskNum -IsOffline $false } catch { }
    exit 1
}

try {
    $reader = New-Object System.IO.BinaryReader($stream)
    
    # Read LBA 1 (GPT Header) - 512 bytes offset
    $stream.Seek(512, [System.IO.SeekOrigin]::Begin) | Out-Null
    $headerSig = $reader.ReadBytes(8)
    $headerSigStr = [System.Text.Encoding]::ASCII.GetString($headerSig)
    
    if ($headerSigStr -ne "EFI PART") {
        Write-Error "Disk is not GPT formatted! Make sure you selected the correct Lumia device."
        $stream.Close()
        Read-Host "Press Enter to exit"
        exit 1
    }
    
    # Read GPT Header info for Partition Entries
    $stream.Seek(512 + 72, [System.IO.SeekOrigin]::Begin) | Out-Null
    $partEntryLBA = $reader.ReadUInt64()
    $numPartEntries = $reader.ReadUInt32()
    $partEntrySize = $reader.ReadUInt32()
    
    # Seek to Partition Array
    $stream.Seek($partEntryLBA * 512, [System.IO.SeekOrigin]::Begin) | Out-Null
    
    $targetPartitionLBA = 0
    $targetPartitionEndLBA = 0
    
    for ($i = 0; $i -lt $numPartEntries; $i++) {
        $entryBytes = $reader.ReadBytes($partEntrySize)
        $firstLBA = [BitConverter]::ToUInt64($entryBytes, 32)
        if ($firstLBA -eq 0) { continue }
        
        $nameBytes = $entryBytes[56..127]
        $name = [System.Text.Encoding]::Unicode.GetString($nameBytes).TrimEnd([char]0)
        
        if ($name -eq $PartitionName) {
            $targetPartitionLBA = $firstLBA
            $targetPartitionEndLBA = [BitConverter]::ToUInt64($entryBytes, 40)
            break
        }
    }
    
    if ($targetPartitionLBA -eq 0) {
        Write-Error "Could not find partition '$PartitionName' in GPT."
        $stream.Close()
        Read-Host "Press Enter to exit"
        exit 1
    }
    
    $targetOffset = $targetPartitionLBA * 512
    $maxBytes = ($targetPartitionEndLBA - $targetPartitionLBA + 1) * 512
    
    Write-Host "[OK] Found partition '$PartitionName' at LBA $targetPartitionLBA (Offset: $targetOffset bytes)"
    
    $imageSize = (Get-Item $imagePath).Length
    if ($imageSize -gt $maxBytes) {
        Write-Error "Image file ($imageSize bytes) is larger than partition capacity ($maxBytes bytes)!"
        $stream.Close()
        Read-Host "Press Enter to exit"
        exit 1
    }
    
    Write-Host ""
    Write-Host "------------------------------------------------------------"
    Write-Host "CAUTION: You are about to flash $imagePath"
    Write-Host "into partition '$PartitionName' on Disk $diskNum."
    Write-Host "This will overwrite existing data in that partition!"
    Write-Host "------------------------------------------------------------"
    Write-Host ""
    $confirm = Read-Host "Are you sure you want to proceed? (Y/N)"
    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Host "Aborted by user."
        $stream.Close()
        exit 0
    }
    
    Write-Host "Flashing image... please wait."
    
    $imageStream = [System.IO.File]::OpenRead($imagePath)
    $stream.Seek($targetOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
    
    $bufferSize = 4096 * 1024 # 4MB buffer
    $buffer = New-Object byte[] $bufferSize
    $bytesRead = 0
    $totalWritten = 0
    
    while (($bytesRead = $imageStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $alignedBytes = $bytesRead
        if (($alignedBytes % 512) -ne 0) {
            $alignedBytes += (512 - ($alignedBytes % 512))
        }
        $stream.Write($buffer, 0, $alignedBytes)
        $totalWritten += $bytesRead
        $percent = [math]::Round(($totalWritten / $imageSize) * 100)
        Write-Progress -Activity "Flashing Image" -Status "$percent% Complete" -PercentComplete $percent
    }
    
    $imageStream.Close()
    
    Write-Host ""
    Write-Host "[SUCCESS] Flashed $totalWritten bytes to '$PartitionName' partition successfully!"
    Write-Host "You may now disconnect the device and force a reboot (Hold Power + Vol Down)."
    
} catch {
    Write-Error "An error occurred during flashing!"
    Write-Error $_.Exception.Message
} finally {
    if ($stream -ne $null) {
        $stream.Close()
    }
    if ($diskNum -ne $null) {
        try {
            Set-Disk -Number $diskNum -IsOffline $false
        } catch {
            Write-Warning "Could not bring disk back online automatically."
        }
    }
}

Write-Host ""
Read-Host "Press Enter to exit"
