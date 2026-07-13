import struct

def test_fat16(img_path):
    print(f"Testing FAT16 image: {img_path}")
    with open(img_path, "rb") as f:
        boot_sector = f.read(512)
        
    # Read boot signature
    sig = boot_sector[510:512]
    if sig != b"\x55\xAA":
        print(f"ERROR: Invalid boot signature {sig}")
        return
    
    # Unpack BPB
    # Offset 11: Bytes per sector (2), Sectors per cluster (1), Reserved sectors (2), Number of FATs (1), Root entries (2)
    bytes_per_sector, sectors_per_cluster, reserved_sectors, num_fats, root_dir_entries = struct.unpack(
        "<HBHBH", boot_sector[11:19]
    )
    print(f"Bytes per sector: {bytes_per_sector}")
    print(f"Sectors per cluster: {sectors_per_cluster}")
    print(f"Reserved sectors: {reserved_sectors}")
    print(f"Number of FATs: {num_fats}")
    print(f"Root directory entries: {root_dir_entries}")
    
    # Sectors per FAT
    sectors_per_fat = struct.unpack("<H", boot_sector[22:24])[0]
    print(f"Sectors per FAT: {sectors_per_fat}")
    
    # Total sectors 32-bit
    total_sectors = struct.unpack("<I", boot_sector[32:36])[0]
    print(f"Total sectors (32-bit): {total_sectors}")
    
    # Volume label
    vol_label = boot_sector[43:54]
    print(f"Volume label: {vol_label}")
    
    # System type
    sys_type = boot_sector[54:62]
    print(f"System type: {sys_type}")
    
    # Check offsets
    root_offset = (reserved_sectors + num_fats * sectors_per_fat) * bytes_per_sector
    print(f"Root directory byte offset: {root_offset}")
    
    # Read root directory
    with open(img_path, "rb") as f:
        f.seek(root_offset)
        root_data = f.read(root_dir_entries * 32)
        
    print("\n--- Root Directory Entries ---")
    for i in range(root_dir_entries):
        entry = root_data[i*32 : (i+1)*32]
        if entry[0] == 0x00:
            # No more entries
            break
        if entry[0] == 0xE5:
            # Deleted entry
            continue
        
        name = entry[0:11].decode('ascii', errors='ignore')
        attr = entry[11]
        start_clus = struct.unpack("<H", entry[26:28])[0]
        size = struct.unpack("<I", entry[28:32])[0]
        
        attr_str = ""
        if attr & 0x10: attr_str += "DIR "
        if attr & 0x08: attr_str += "VOL "
        
        print(f"Entry {i}: Name='{name}', Attr={attr:#x} ({attr_str}), Cluster={start_clus}, Size={size} bytes")

if __name__ == "__main__":
    import os
    if os.path.exists("build/efi_part.img"):
        test_fat16("build/efi_part.img")
    else:
        print("build/efi_part.img not found!")
