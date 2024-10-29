detect_partitions()
{
    DPP=$(parted /dev/block/mmcblk0 print | grep -Ev '^(Model:|Disk|Sector size|Partition Table|Number)' |
                    grep -w "DPP" | awk '{print $1}')
    echo "DPP partition is GPT nr. $DPP"
    PERSIST=$(parted /dev/block/mmcblk0 print | grep -Ev '^(Model:|Disk|Sector size|Partition Table|Number)' |
                    grep -w "persist" | awk '{print $1}')
    echo "persist partition is GPT nr. $PERSIST"
}
mount_partitions()
{
    mkdir -p DPP
    mkdir -p persist
    mount /dev/block/mmcblk0p${DPP} /DPP/
    mount /dev/block/mmcblk0p${PERSIST} /persist/
}

umount_partitions()
{
    umount /DPP/
    umount /persist/
}

provision()
{
    extract_wlan_mac
    write_bdaddr
    provision_modem
}

provision_modem()
{
    dd if=/dev/block/bootdevice/by-name/MODEM_FS1 of=/dev/block/bootdevice/by-name/modemst1
    dd if=/dev/block/bootdevice/by-name/MODEM_FS2 of=/dev/block/bootdevice/by-name/modemst2
    dd if=/dev/block/bootdevice/by-name/MODEM_FSC of=/dev/block/bootdevice/by-name/fsc
    dd if=/dev/block/bootdevice/by-name/MODEM_FSG of=/dev/block/bootdevice/by-name/fsg
    dd if=/dev/block/bootdevice/by-name/SSD of=/dev/block/bootdevice/by-name/ssd
}

extract_wlan_mac()
{
    # Input file
    if="DPP/QCOM/WLAN.PROVISION"
    # Output file
    of="/persist/wlan_mac.bin"

    # Function to extract 6 bytes and convert to uppercase
    extract_mac_address() {
        local start_byte=$1
        hexdump -v -e '6/1 "%02X"' -s "$start_byte" -n 6 "$if" | tr 'a-f' 'A-F'
    }

    # Extract each MAC address
    intf0_mac=$(extract_mac_address 3)
    intf1_mac=$(extract_mac_address 9)
    intf2_mac=$(extract_mac_address 15)
    intf3_mac=$(extract_mac_address 21)

    # Write the MAC addresses to the output file
    {
        echo "Intf0MacAddress=$intf0_mac"
        echo "Intf1MacAddress=$intf1_mac"
        echo "Intf2MacAddress=$intf2_mac"
        echo "Intf3MacAddress=$intf3_mac"
    } > "$of"
}

write_bdaddr()
{
# Input file
if="/DPP/QCOM/BT.PROVISION"
# Output file
of="/persist/bdaddr.txt"

# Extract 6 bytes starting from the 4th byte
mac_address=$(hexdump -v -e '6/1 "%02X"' -s 2 "$if" | tr 'a-f' 'A-F')

# Format the extracted bytes into 00:00:00:00:00:00
formatted_mac=$(echo "$mac_address" | sed 's/\(..\)/\1:/g; s/:$//')

# Write the formatted MAC address to the output file
echo "$formatted_mac" > "$of"

}
detect_partitions
mount_partitions
provision
umount_partitions