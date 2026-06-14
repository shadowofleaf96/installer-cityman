#!/usr/bin/env python3
"""
Extract modem partition from a Lumia FFU file.
Usage: python extract_modem.py <ffu_file> [output_dir]
"""
import struct
import sys
import os

def align_up(value, alignment):
    """Align value up to the next multiple of alignment."""
    if alignment == 0:
        return value
    return ((value + alignment - 1) // alignment) * alignment

def parse_ffu(ffu_path, output_dir='.'):
    file_size = os.path.getsize(ffu_path)
    print(f"FFU file: {ffu_path}")
    print(f"File size: {file_size / 1024 / 1024:.1f} MB")
    print()

    with open(ffu_path, 'rb') as f:
        # ============================================
        # 1. Read Security Header (32 bytes at offset 0)
        # ============================================
        sec_data = f.read(32)
        sec_cb_size = struct.unpack_from('<I', sec_data, 0)[0]
        sec_signature = sec_data[4:16]
        chunk_size_kb = struct.unpack_from('<I', sec_data, 16)[0]
        hash_algo = struct.unpack_from('<I', sec_data, 20)[0]
        catalog_size = struct.unpack_from('<I', sec_data, 24)[0]
        hash_table_size = struct.unpack_from('<I', sec_data, 28)[0]
        chunk_size = chunk_size_kb * 1024

        print(f"[Security Header]")
        print(f"  Signature: {sec_signature}")
        print(f"  Chunk size: {chunk_size} bytes ({chunk_size_kb} KB)")
        print(f"  Catalog size: {catalog_size}")
        print(f"  Hash table size: {hash_table_size}")
        print()

        # ============================================
        # 2. Calculate offsets to subsequent sections
        # ============================================
        catalog_offset = sec_cb_size
        hash_offset = catalog_offset + catalog_size
        # Everything up to here needs to be aligned to chunk boundary
        image_header_offset = align_up(hash_offset + hash_table_size, chunk_size)

        print(f"[Offsets]")
        print(f"  Catalog: {catalog_offset}")
        print(f"  Hash table: {hash_offset}")
        print(f"  Image header: {image_header_offset}")

        # ============================================
        # 3. Read Image Header
        # ============================================
        f.seek(image_header_offset)
        img_data = f.read(24)
        img_cb_size = struct.unpack_from('<I', img_data, 0)[0]
        img_signature = img_data[4:16]
        manifest_length = struct.unpack_from('<I', img_data, 16)[0]
        img_chunk_size = struct.unpack_from('<I', img_data, 20)[0]

        print(f"\n[Image Header]")
        print(f"  Signature: {img_signature}")
        print(f"  Manifest length: {manifest_length}")
        print(f"  Image chunk size: {img_chunk_size}")

        # ============================================
        # 4. Read Store Header and Write Descriptors
        # ============================================
        store_offset = image_header_offset + align_up(img_cb_size + manifest_length, chunk_size)
        f.seek(store_offset)
        store_data = f.read(248)
        
        major_ver = struct.unpack_from('<H', store_data, 4)[0]
        write_desc_count = 0
        
        if major_ver == 1:
            write_desc_count = struct.unpack_from('<I', store_data, 208)[0]
            f.seek(store_offset + 248)
        else:
            write_desc_count = struct.unpack_from('<I', store_data, 208)[0]
            device_path_length = struct.unpack_from('<H', store_data, 246)[0]
            f.seek(store_offset + 248 + device_path_length * 2)

        # Skip validation descriptors (if any)
        validate_desc_count = struct.unpack_from('<I', store_data, 216)[0]
        for _ in range(validate_desc_count):
            sector_idx = struct.unpack('<I', f.read(4))[0]
            sector_offset = struct.unpack('<I', f.read(4))[0]
            byte_count = struct.unpack('<I', f.read(4))[0]
            f.seek(byte_count, 1)

        # Now at the exact start of write descriptors
        desc_offset = f.tell()
        print(f"  Write descriptors start at: {desc_offset} (0x{desc_offset:X})")

        print(f"\n[Parsing {write_desc_count} write descriptors...]")

        dest_to_file_offset = {}
        source_idx = 0
        
        # Read the raw descriptors sequentially
        for i in range(write_desc_count):
            location_count = struct.unpack('<I', f.read(4))[0]
            block_count = struct.unpack('<I', f.read(4))[0]
            
            locations = []
            for j in range(location_count):
                access_method = struct.unpack('<I', f.read(4))[0]
                dest_block = struct.unpack('<I', f.read(4))[0]
                locations.append((access_method, dest_block))
                
            # Assume 1 payload block per descriptor based on FfuConvert logic.
            # FfuConvert ignores block_count and consumes 1 block per descriptor.
            # But wait, what if FfuConvert is wrong and block_count is correct?
            # We will use block_count to advance source_idx, but map 1 block if FfuConvert failed due to it,
            # actually FfuConvert's target offset is location.dwBlockIndex * BlockSize.
            # Let's map each block in block_count to dest_block + b
            desc_payload_blocks = block_count if block_count > 0 else 1 # some tools assume 1

            for access_method, dest_block in locations:
                if access_method == 2:
                    continue # DISK_END
                for b in range(block_count):
                    # We don't know data_start yet, so we store the block index
                    dest_to_file_offset[dest_block + b] = source_idx + b

            source_idx += block_count

        # ReadPadding: align to chunk_size
        padding = f.tell() % chunk_size
        if padding > 0:
            f.seek(chunk_size - padding, 1)
            
        data_start = f.tell()
        print(f"  Data blocks start at offset: {data_start} (0x{data_start:X})")

        # Convert dest_to_file_offset from block indices to absolute file offsets
        block_size = struct.unpack_from('<I', store_data, 204)[0]
        if block_size == 0:
            block_size = 131072
        for k in dest_to_file_offset:
            dest_to_file_offset[k] = data_start + dest_to_file_offset[k] * block_size

        print(f"  Total source blocks: {source_idx}")
        print(f"  Total mapped disk blocks: {len(dest_to_file_offset)}")

        # ============================================
        # 7. Reconstruct GPT from block map
        # ============================================
        print(f"\n[Reconstructing partition table...]")

        if 0 in dest_to_file_offset:
            print(f"  Block 0 mapped to file offset: {dest_to_file_offset[0]}")
        else:
            print(f"  WARNING: Block 0 not found in block map!")

        # Read GPT: MBR is at LBA 0, GPT header at LBA 1
        # With 128KB blocks and 512-byte sectors, block 0 = LBA 0-255
        sector_size = 512
        sectors_per_block = block_size // sector_size

        # Read first disk block (contains MBR + GPT header + partition entries)
        gpt_raw = bytearray(block_size)  # One full 128KB block = 256 sectors
        if 0 in dest_to_file_offset:
            f.seek(dest_to_file_offset[0])
            gpt_raw = bytearray(f.read(block_size))
            print(f"  Read block 0 from file offset: {dest_to_file_offset[0]}")
        else:
            print(f"  ERROR: Block 0 not found in block map!")
            sys.exit(1)

        # Parse GPT
        gpt_sig = gpt_raw[sector_size:sector_size + 8]
        if gpt_sig != b'EFI PART':
            print(f"  ERROR: GPT signature not found! Got: {gpt_sig}")
            print(f"  The FFU format might be different than expected.")
            sys.exit(1)

        print(f"  [OK] GPT signature found!")

        # Parse GPT header
        gpt_header = gpt_raw[sector_size:sector_size + 92]
        part_entry_lba = struct.unpack_from('<Q', gpt_header, 72)[0]
        num_entries = struct.unpack_from('<I', gpt_header, 80)[0]
        entry_size = struct.unpack_from('<I', gpt_header, 84)[0]

        print(f"  Partition entries at LBA: {part_entry_lba}")
        print(f"  Number of entries: {num_entries}")
        print(f"  Entry size: {entry_size}")

        # Read partition entries
        # They might extend beyond our initial 34 sectors
        entries_start = part_entry_lba * sector_size
        entries_total_size = num_entries * entry_size
        entries_end_lba = part_entry_lba + (entries_total_size + sector_size - 1) // sector_size

        # Read all entry sectors
        entries_raw = bytearray(entries_total_size)
        for lba in range(part_entry_lba, entries_end_lba + 1):
            disk_block = lba // sectors_per_block
            block_offset = (lba % sectors_per_block) * sector_size

            if disk_block in dest_to_file_offset:
                file_offset = dest_to_file_offset[disk_block] + block_offset
                f.seek(file_offset)
                data = f.read(sector_size)
                rel_offset = (lba - part_entry_lba) * sector_size
                end = min(rel_offset + sector_size, entries_total_size)
                entries_raw[rel_offset:end] = data[:end - rel_offset]

        # Parse partition entries
        partitions = []
        for i in range(num_entries):
            entry = entries_raw[i * entry_size:(i + 1) * entry_size]
            if len(entry) < 128:
                break
            type_guid = entry[0:16]
            if type_guid == b'\x00' * 16:
                continue
            first_lba = struct.unpack_from('<Q', entry, 32)[0]
            last_lba = struct.unpack_from('<Q', entry, 40)[0]
            name_raw = entry[56:128]
            name = name_raw.decode('utf-16-le', errors='ignore').rstrip('\x00')
            size_bytes = (last_lba - first_lba + 1) * sector_size
            size_mb = size_bytes / 1024 / 1024
            partitions.append({
                'name': name,
                'first_lba': first_lba,
                'last_lba': last_lba,
                'size_bytes': size_bytes,
                'size_mb': size_mb,
            })

        # Print all partitions
        print(f"\n{'='*70}")
        print(f"  {'#':>3}  {'Name':20s}  {'Start LBA':>12}  {'End LBA':>12}  {'Size':>10}")
        print(f"{'='*70}")
        modem_part = None
        for idx, p in enumerate(partitions):
            marker = ""
            # Look for modem-related partitions
            name_lower = p['name'].lower()
            if name_lower in ('mmos', 'modem'):
                marker = " <-- MODEM FIRMWARE"
                modem_part = p
            elif 'modem' in name_lower:
                marker = " <-- modem related"

            if p['size_mb'] >= 1:
                size_str = f"{p['size_mb']:.1f} MB"
            else:
                size_str = f"{p['size_bytes']} B"

            print(f"  {idx+1:>3}  {p['name']:20s}  {p['first_lba']:>12}  {p['last_lba']:>12}  {size_str:>10}{marker}")
        print(f"{'='*70}")

        print("\n[Extracting ALL partitions...]")
        for part in partitions:
            output_file = os.path.join(output_dir, f"{part['name']}.img")
            print(f"\n[Extracting partition: {part['name']}]")
            print(f"  LBA range: {part['first_lba']} - {part['last_lba']}")
            print(f"  Size: {part['size_mb']:.1f} MB")

            extracted = 0
            total_sectors = part['last_lba'] - part['first_lba'] + 1
            missing_blocks = 0

            with open(output_file, 'wb') as out:
                for lba in range(part['first_lba'], part['last_lba'] + 1):
                    disk_block = lba // sectors_per_block
                    block_offset = (lba % sectors_per_block) * sector_size

                    if disk_block in dest_to_file_offset:
                        file_offset = dest_to_file_offset[disk_block] + block_offset
                        if file_offset + sector_size <= file_size:
                            f.seek(file_offset)
                            data = f.read(sector_size)
                            out.write(data)
                        else:
                            out.write(b'\x00' * sector_size)
                            missing_blocks += 1
                    else:
                        out.write(b'\x00' * sector_size)
                        missing_blocks += 1

                    extracted += 1
                    if extracted % 10000 == 0 or extracted == total_sectors:
                        pct = extracted * 100 // total_sectors
                        print(f"  Progress: {pct}% ({extracted}/{total_sectors} sectors)", end='\r')

            print()
            result_size = os.path.getsize(output_file)
            print(f"  [OK] Extracted to: {output_file} ({result_size / 1024 / 1024:.1f} MB)")
            if missing_blocks > 0:
                pct = missing_blocks * 100 // total_sectors
                print(f"  WARNING: {missing_blocks} sectors ({pct}%) were not found in FFU (filled with zeros)")

    print("\nDone!")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python extract_modem.py <ffu_file> [output_dir]")
        print("Example: python extract_modem.py firmware.ffu ./output")
        sys.exit(1)

    ffu_file = sys.argv[1]
    out_dir = sys.argv[2] if len(sys.argv) > 2 else '.'

    if not os.path.exists(ffu_file):
        print(f"Error: File not found: {ffu_file}")
        sys.exit(1)

    os.makedirs(out_dir, exist_ok=True)
    parse_ffu(ffu_file, out_dir)
