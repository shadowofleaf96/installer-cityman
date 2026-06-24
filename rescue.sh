#!/bin/bash

# SYNOPSIS
#     Rescues a Lumia 950 XL from a bootloop by directly writing to the Android boot/recovery
#     partitions via USB Mass Storage Mode.

if [ "$EUID" -ne 0 ]; then
    echo "Requesting administrative privileges..."
    exec sudo "$0" "$@"
    exit $?
fi

IMAGE_NAME=${1:-twrp.img}
PARTITION_NAME=${2:-boot}
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
IMAGE_PATH="${BASE_DIR}/DATA/${IMAGE_NAME}"

echo "============================================================"
echo "  Lumia 950 XL Bootloop Rescue (Mass Storage Mode)"
echo "============================================================"
echo ""
echo "Target Image     : DATA/$IMAGE_NAME"
echo "Target Partition : $PARTITION_NAME"
echo ""

if [ ! -f "$IMAGE_PATH" ]; then
    echo "Could not find image at: $IMAGE_PATH"
    read -p "Press Enter to exit"
    exit 1
fi

echo "Scanning for partition '$PARTITION_NAME'..."

# Use lsblk to find partitions named $PARTITION_NAME
PART_PATHS=$(lsblk -r -o PATH,PARTLABEL | awk -v part="$PARTITION_NAME" 'toupper($2) == toupper(part) {print $1}')

if [ -z "$PART_PATHS" ]; then
    echo "No partition named '$PARTITION_NAME' found!"
    echo "Ensure your phone is in Mass Storage Mode and connected."
    read -p "Press Enter to exit"
    exit 1
fi

mapfile -t CANDIDATES <<< "$PART_PATHS"

if [ ${#CANDIDATES[@]} -eq 0 ]; then
    echo "No partition named '$PARTITION_NAME' found!"
    exit 1
fi

TARGET_PART=""
if [ ${#CANDIDATES[@]} -gt 1 ]; then
    echo "Multiple partitions found. Please select the correct one (check disk size):"
    for i in "${!CANDIDATES[@]}"; do
        path="${CANDIDATES[$i]}"
        size=$(lsblk -d -n -o SIZE "$path")
        parent=$(lsblk -n -o PKNAME "$path")
        model=""
        if [ -n "$parent" ]; then
            model=$(lsblk -d -n -o MODEL "/dev/$parent")
        fi
        echo "  [$i] $path ($size) on $model"
    done
    read -p "Enter choice [0-$(( ${#CANDIDATES[@]} - 1 ))]: " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 0 ] || [ "$choice" -ge ${#CANDIDATES[@]} ]; then
        echo "Invalid selection."
        exit 1
    fi
    TARGET_PART="${CANDIDATES[$choice]}"
else
    TARGET_PART="${CANDIDATES[0]}"
    size=$(lsblk -d -n -o SIZE "$TARGET_PART")
    echo "Found partition $TARGET_PART ($size)"
fi

if [ -z "$TARGET_PART" ] || [ ! -e "$TARGET_PART" ]; then
    echo "Invalid target partition."
    exit 1
fi

echo ""
echo "------------------------------------------------------------"
echo "CAUTION: You are about to flash $IMAGE_PATH"
echo "into partition '$PARTITION_NAME' at $TARGET_PART."
echo "This will overwrite existing data in that partition!"
echo "------------------------------------------------------------"
echo ""
read -p "Are you sure you want to proceed? (Y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted by user."
    exit 0
fi

echo "Flashing image... please wait."
if ! dd if="$IMAGE_PATH" of="$TARGET_PART" bs=4M status=progress; then
    echo "An error occurred during flashing!"
    exit 1
fi

echo ""
echo "[SUCCESS] Flashed successfully to '$PARTITION_NAME'!"
echo "You may now disconnect the device and force a reboot (Hold Power + Vol Down)."
echo ""
read -p "Press Enter to exit"
