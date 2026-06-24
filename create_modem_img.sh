#!/bin/bash

IMG_FILE="/home/unk/Bureau/modem.img"
FIRMWARE_DIR="/media/unk/LinuxData/android/LineageOS-18.1/vendor/msft/cityman/proprietary/vendor/firmware"

echo "Creating 70MB empty image..."
dd if=/dev/zero of=$IMG_FILE bs=1M count=70

echo "Formatting as FAT16..."
mkfs.fat -F 16 $IMG_FILE

if command -v mcopy &> /dev/null; then
    echo "mtools found! Copying files without sudo..."
    mmd -i $IMG_FILE ::/image
    mcopy -i $IMG_FILE $FIRMWARE_DIR/*.mdt ::/image/
    mcopy -i $IMG_FILE $FIRMWARE_DIR/*.b* ::/image/
    
    # TrustZone expects the Modem Boot Authenticator to be named mba.mbn
    if [ -f "$FIRMWARE_DIR/mba.b00" ]; then
        mcopy -i $IMG_FILE "$FIRMWARE_DIR/mba.b00" ::/image/mba.mbn
    fi
else
    echo "mtools not found. Will use sudo to mount and copy."
    mkdir -p /tmp/modem_mnt
    sudo mount -o loop $IMG_FILE /tmp/modem_mnt
    sudo mkdir -p /tmp/modem_mnt/image
    sudo cp $FIRMWARE_DIR/*.mdt /tmp/modem_mnt/image/
    sudo cp $FIRMWARE_DIR/*.b* /tmp/modem_mnt/image/
    
    # TrustZone expects the Modem Boot Authenticator to be named mba.mbn
    if [ -f "$FIRMWARE_DIR/mba.b00" ]; then
        sudo cp "$FIRMWARE_DIR/mba.b00" /tmp/modem_mnt/image/mba.mbn
    fi
    
    sudo umount /tmp/modem_mnt
fi

echo "Success! $IMG_FILE has been created in your Bureau folder."
