#!/bin/bash

#backup partitions
dump_provisioned()
{
    declare -a backupPartitions=("APDP" "DBI" "DDR" "DPO" "DPP" "LIMITS" "MODEM_FS1" "MODEM_FS2" 
                                "MODEM_FSC" "MODEM_FSG" "MSADP" "SEC" "SSD" "UEFI_BS_NV" "UEFI_RT_NV")
    
    mkdir -p backup
    echo "Dumping provisioned partitions"
    for i in "${backupPartitions[@]}"
    do
        echo "Dumping $i..."
        dd if=/dev/block/platform/soc.0/f9824900.sdhci/by-name/$i of=backup/$i.bin
    done
}
#########################################################
############# detect mainOS and data #####################
##########################################################
detect_partitions()
{
    MMOS=$(parted /dev/block/mmcblk0 print | grep -Ev '^(Model:|Disk|Sector size|Partition Table|Number)' |
                    grep "MMOS" | awk '{print $1}')
    MAINOS=$(parted /dev/block/mmcblk0 print | grep -Ev '^(Model:|Disk|Sector size|Partition Table|Number)' |
                    grep "MainOS" | awk '{print $1}')
    echo "MainOS partition is GPT nr. $MAINOS"
    DATA=$(parted /dev/block/mmcblk0 print | grep -Ev '^(Model:|Disk|Sector size|Partition Table|Number)' |
                    grep "Data" | awk '{print $1}')
    echo "Data partition is GPT nr. $DATA"

    if [ -z "$DATA" ]; then
        while true; do
            read -p "Data partition not found, proceed? " yn
            case $yn in
                [Yy]* ) nodata=1; break;;
                [Nn]* ) exit;;
                * ) echo "Please answer yes or no.";;
            esac
        done
    fi

    if [ -z "$MAINOS" ]; then
        while true; do
            read -p "MainOS partition not found, proceed? " yn
            case $yn in
                [Yy]* ) nomainos=1; break;;
                [Nn]* ) exit;;
                * ) echo "Please answer yes or no.";;
            esac
        done
    fi

    if [ -z "$MMOS" ]; then
        while true; do
            read -p "MMOS partition not found, proceed? " yn
            case $yn in
                [Yy]* ) nommos=1; break;;
                [Nn]* ) exit;;
                * ) echo "Please answer yes or no.";;
            esac
        done
    fi
}
#########################################################
######## erase partitions and create Android ones #######
#########################################################
partition()
{ 
    if [ ! -z "$nodata" ]; then
        echo "Will not delete Data"
    else
        parted /dev/block/mmcblk0 --script rm $DATA
    fi

    if [ ! -z "$nomainos" ]; then
        echo "Will not delete MainOS"
    else
        parted /dev/block/mmcblk0 --script rm $MAINOS
    fi

    if [ ! -z "$nommos" ]; then
        echo "Will not delete MMOS"
    else
        parted /dev/block/mmcblk0 --script rm $MMOS
    fi
    echo "Creating Android partitions"
    declare -a androidPartitions=("aboot"      "1MiB"     "fat16"
                                  "boot"       "34MiB"    "ext4"
                                  "recovery"   "34MiB"    "ext4"
                                  "misc"       "16MiB"    "ext4"
                                  "modem"      "70MiB"    "fat16"
                                  "cache"      "150MiB"   "ext4"
                                  "persist"    "68MiB"    "ext4"
                                  "persistent" "68MiB"    "ext4"
                                  "fsc"        "1MiB"     "ext4"
                                  "fsg"        "2MiB"     "ext4"
                                  "metadata"   "2MiB"     "ext4"
                                  "ssd"        "2MiB"     "ext4"
                                  "modemst1"   "2MiB"     "ext4"
                                  "modemst2"   "2MiB"     "ext4"
                                  "vendor"     "260MiB"   "ext4"
                                  "system"     "3072MiB"  "ext4"
                                  "userdata"   "100%"     "ext4");

    for ((i=0; i<${#androidPartitions[@]}; i+=3)); do
        last_line=$(parted /dev/block/mmcblk0 unit MiB print | tail -n 2)

        # Extract the End size (second column)
        end_size=$(echo "$last_line" | awk '{print $3}')

        # Use the extracted End size for further processing
        echo "The end of the last partition is at: $end_size"
        if [ ${androidPartitions[i+1]} != "100%" ];then
            total_size=$(( ${androidPartitions[i+1]//[^0-9]/} + ${end_size//[^0-9]/} ))
            echo $total_size
        else
            total_size="100%"
        fi
        #echo "Partition: ${androidPartitions[i]}, Start: $end_size, Size: ${total_size}, Filesystem:${androidPartitions[i+2]}"
        parted /dev/block/mmcblk0 unit MiB --script mkpart "${androidPartitions[i]}" "$end_size" "$total_size"

        # Wait for partition table update
        sleep 1
        sync
        sync
        ###format partitions###
        newpart=$(parted /dev/block/mmcblk0 print | grep -Ev '^(Model:|Disk|Sector size|Partition Table|Number)' |
                    grep "${androidPartitions[i]}" | awk '{print $1}')
        if [[ "${androidPartitions[i+2]}" == "fat16" ]]; then
        mkfs.fat /dev/block/mmcblk0p${newpart}
        elif [[ "${androidPartitions[i+2]}" == "ext4" ]]; then
        mke2fs -t ext4 /dev/block/mmcblk0p${newpart}
        fi
    done
}
#################
use_aboot()
{
    efiesp=$(parted /dev/block/mmcblk0 print | grep -Ev '^(Model:|Disk|Sector size|Partition Table|Number)' |
                    grep "EFIESP" | awk '{print $1}')
    aboot=$(parted /dev/block/mmcblk0 print | grep -Ev '^(Model:|Disk|Sector size|Partition Table|Number)' |
                    grep "aboot" | awk '{print $1}')

    mkdir -p /efiesp
    mkdir -p /aboot
    mount /dev/block/mmcblk0p${efiesp} /efiesp/
    mount /dev/block/mmcblk0p${aboot} /aboot/
    cp /efiesp/emmc_appsboot.mbn /aboot/
    rm /efiesp/emmc_appsboot.mbn
}
##############################

dump_provisioned
detect_partitions
partition
use_aboot