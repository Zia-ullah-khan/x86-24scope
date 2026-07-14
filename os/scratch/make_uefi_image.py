import os
import struct

def make_fat16_image(image_path, src_dir, size_mb=16):
    print(f"Creating FAT16 image at {image_path} from {src_dir} ({size_mb}MB)...")
    
    # FAT16 parameters
    sector_size = 512
    sectors_per_cluster = 16
    cluster_size = sector_size * sectors_per_cluster # 8192 bytes
    reserved_sectors = 4
    num_fats = 2
    root_dir_entries = 512
    root_dir_sectors = (root_dir_entries * 32) // sector_size # 32 sectors
    
    total_sectors = (size_mb * 1024 * 1024) // sector_size
    fat_size_sectors = 128
    
    # Initialize blank image
    img_data = bytearray(total_sectors * sector_size)
    
    # 1. Write Boot Sector (LBA 0)
    # OEM Name: "MSWIN4.1"
    oem = b"MSWIN4.1"
    # BPB (BIOS Parameter Block)
    bpb = struct.pack(
        "<HBHBHHBHHHI",
        sector_size,          # Bytes per sector
        sectors_per_cluster,  # Sectors per cluster
        reserved_sectors,     # Reserved sectors
        num_fats,             # Number of FATs
        root_dir_entries,     # Root directory entries
        0,                    # Total sectors 16-bit
        0xF8,                 # Media descriptor (hard disk)
        fat_size_sectors,     # Sectors per FAT
        63,                   # Sectors per track
        255,                  # Number of heads
        0                     # Hidden sectors
    )
    # Total sectors 32-bit
    total_sectors_32 = total_sectors
    bpb_ext = struct.pack(
        "<IBBBI",
        total_sectors_32,     # Total sectors 32-bit (offset 32)
        0x80,                 # Drive number (offset 36)
        0,                    # Reserved (offset 37)
        0x29,                 # Extended boot signature (offset 38)
        0x12345678            # Volume ID (offset 39)
    )
    label = b"24SCOPE    "      # Volume label (11 bytes)
    sys_type = b"FAT16   "     # Filesystem type (8 bytes)
    
    # Assemble Boot Sector
    img_data[0:3] = b"\xEB\x3C\x90" # Jump instruction
    img_data[3:11] = oem
    img_data[11:32] = bpb
    img_data[32:43] = bpb_ext
    img_data[43:54] = label
    img_data[54:62] = sys_type
    img_data[510:512] = b"\x55\xAA" # Boot signature
    
    # Calculate offsets
    fat1_offset = reserved_sectors * sector_size
    fat2_offset = (reserved_sectors + fat_size_sectors) * sector_size
    root_offset = (reserved_sectors + num_fats * fat_size_sectors) * sector_size
    data_offset = root_offset + root_dir_sectors * sector_size
    
    # Initialize FATs (first two entries are reserved)
    img_data[fat1_offset : fat1_offset + 4] = b"\xF8\xFF\xFF\xFF"
    img_data[fat2_offset : fat2_offset + 4] = b"\xF8\xFF\xFF\xFF"
    
    # Helper to allocate clusters
    free_cluster = 2
    
    def write_fat_entry(cluster, val):
        offset1 = fat1_offset + cluster * 2
        offset2 = fat2_offset + cluster * 2
        img_data[offset1 : offset1 + 2] = struct.pack("<H", val)
        img_data[offset2 : offset2 + 2] = struct.pack("<H", val)
        
    def allocate_chain(size_bytes):
        nonlocal free_cluster
        needed_clusters = (size_bytes + cluster_size - 1) // cluster_size
        if needed_clusters == 0:
            return 0
        
        start = free_cluster
        for i in range(needed_clusters):
            curr = free_cluster
            free_cluster += 1
            if i == needed_clusters - 1:
                write_fat_entry(curr, 0xFFFF) # End of chain
            else:
                write_fat_entry(curr, free_cluster)
        return start

    def write_cluster_data(cluster, data):
        offset = data_offset + (cluster - 2) * cluster_size
        img_data[offset : offset + len(data)] = data

    # 2. Build Directory tree and files
    def format_short_name(name, is_dir=False):
        name = name.upper()
        if is_dir:
            base = name.replace(" ", "")[:8]
            ext = ""
        else:
            parts = name.rsplit(".", 1)
            base = parts[0].replace(" ", "")[:8]
            ext = parts[1].replace(" ", "")[:3] if len(parts) > 1 else ""
        return f"{base:<8}{ext:<3}".encode("ascii", "ignore")

    def short_name_checksum(short_name):
        s = 0
        for b in short_name:
            s = ((s & 1) << 7) + (s >> 1) + b
            s &= 0xFF
        return s

    def write_lfn_entries(dir_offset, entry_idx, long_name, short_name):
        """Write FAT long-file-name entries; returns next entry index."""
        name_utf16 = long_name.encode("utf-16-le") + b"\x00\x00"
        # Pad to 13-char (26-byte) chunks
        while len(name_utf16) % 26:
            name_utf16 += b"\xFF\xFF"
        chunks = [name_utf16[i:i + 26] for i in range(0, len(name_utf16), 26)]
        checksum = short_name_checksum(short_name)
        # On disk: last chunk first, with 0x40 bit on the first-written (highest seq)
        for seq_idx, chunk in enumerate(reversed(chunks)):
            seq = len(chunks) - seq_idx
            if seq_idx == 0:
                seq |= 0x40
            eoff = dir_offset + entry_idx * 32
            entry = bytearray(32)
            entry[0] = seq
            entry[11] = 0x0F
            entry[13] = checksum
            # chars 1-5 @1, 6-11 @14, 12-13 @28
            entry[1:11] = chunk[0:10]
            entry[14:26] = chunk[10:22]
            entry[28:32] = chunk[22:26]
            img_data[eoff:eoff + 32] = entry
            entry_idx += 1
        return entry_idx

    def add_to_directory(dir_offset, local_path, max_entries):
        nonlocal free_cluster
        # Prefer small dirs / EFI first so assets fit early in the RAM disk window
        entries = sorted(
            os.listdir(local_path),
            key=lambda n: (
                0 if n.upper() == "EFI" else
                1 if n.upper().startswith("PLANE") else
                2 if n.upper() == "MAPS" else 3,
                n.lower(),
            ),
        )
        entry_idx = 0

        for name in entries:
            full_path = os.path.join(local_path, name)
            is_directory = os.path.isdir(full_path)
            short_name = format_short_name(name, is_directory)
            attr = 0x10 if is_directory else 0x00
            size = 0 if is_directory else os.path.getsize(full_path)

            lfn_needed = 1 + (len(name.encode("utf-16-le")) + 2 + 25) // 26
            if entry_idx + lfn_needed + 1 > max_entries:
                print(f"WARNING: directory full, skipping {name}")
                break

            if is_directory:
                start_clus = free_cluster
                free_cluster += 1
                write_fat_entry(start_clus, 0xFFFF)
                dir_offset_child = data_offset + (start_clus - 2) * cluster_size
                add_to_directory(dir_offset_child, full_path, cluster_size // 32)
            else:
                with open(full_path, "rb") as f:
                    data = f.read()
                start_clus = allocate_chain(len(data))
                if start_clus > 0:
                    write_cluster_data(start_clus, data)

            entry_idx = write_lfn_entries(dir_offset, entry_idx, name, short_name)
            entry_offset = dir_offset + entry_idx * 32
            img_data[entry_offset:entry_offset + 11] = short_name
            img_data[entry_offset + 11] = attr
            img_data[entry_offset + 26:entry_offset + 28] = struct.pack("<H", start_clus & 0xFFFF)
            img_data[entry_offset + 20:entry_offset + 22] = struct.pack("<H", (start_clus >> 16) & 0xFFFF)
            img_data[entry_offset + 28:entry_offset + 32] = struct.pack("<I", size)
            entry_idx += 1

    add_to_directory(root_offset, src_dir, root_dir_entries)

    with open(image_path, "wb") as f:
        f.write(img_data)
    print("FAT16 image generation complete!")

def make_bootable_iso(iso_path, efi_img_path):
    print(f"Generating bootable ISO at {iso_path}...")
    
    # ISO9660 parameters
    sector_size = 2048
    
    # Read efi_img
    with open(efi_img_path, "rb") as f:
        efi_data = f.read()
    
    # Padding efi_img to 2048-byte boundary
    pad_len = (2048 - (len(efi_data) % 2048)) % 2048
    efi_data += b"\x00" * pad_len
    efi_sectors = len(efi_data) // 2048
    
    # ISO Layout:
    # Sector 0..15: System Area (zeroes)
    # Sector 16: Primary Volume Descriptor (PVD)
    # Sector 17: Boot Record Volume Descriptor (El Torito)
    # Sector 18: Volume Descriptor Set Terminator
    # Sector 19: Boot Catalog (El Torito)
    # Sector 20: Root directory extent
    # Sector 21..X: efi_part.img
    
    root_dir_lba = 20
    boot_image_lba = 21
    iso_data = bytearray(boot_image_lba * sector_size)
    
    # 1. Primary Volume Descriptor (Sector 16)
    pvd_offset = 16 * sector_size
    iso_data[pvd_offset] = 1 # Type
    iso_data[pvd_offset + 1 : pvd_offset + 6] = b"CD001"
    iso_data[pvd_offset + 6] = 1 # Version
    iso_data[pvd_offset + 8 : pvd_offset + 40] = b"24SCOPE".ljust(32) # System ID
    iso_data[pvd_offset + 40 : pvd_offset + 72] = b"24SCOPE".ljust(32) # Volume ID
    # Volume space size
    volume_size = boot_image_lba + efi_sectors
    iso_data[pvd_offset + 80 : pvd_offset + 84] = struct.pack("<I", volume_size)
    iso_data[pvd_offset + 84 : pvd_offset + 88] = struct.pack(">I", volume_size)
    # Volume set size = 1, sequence number = 1 (both-endian 16-bit)
    iso_data[pvd_offset + 120 : pvd_offset + 124] = struct.pack("<H", 1) + struct.pack(">H", 1)
    iso_data[pvd_offset + 124 : pvd_offset + 128] = struct.pack("<H", 1) + struct.pack(">H", 1)
    # Logical block size = 2048 (both-endian 16-bit)
    iso_data[pvd_offset + 128 : pvd_offset + 132] = struct.pack("<H", 2048) + struct.pack(">H", 2048)
    # Path table size = 0
    # Root directory record (34 bytes at offset 156)
    def make_dir_record(lba, file_id):
        rec = bytearray(34)
        rec[0] = 34 # Record length
        rec[2:6] = struct.pack("<I", lba) # Extent LBA
        rec[6:10] = struct.pack(">I", lba)
        rec[10:14] = struct.pack("<I", 2048) # Extent size
        rec[14:18] = struct.pack(">I", 2048)
        rec[25] = 0x02 # Directory flag
        rec[28:32] = struct.pack("<H", 1) + struct.pack(">H", 1) # Volume sequence number
        rec[32] = 1 # File ID length
        rec[33] = file_id
        return rec
    
    iso_data[pvd_offset + 156 : pvd_offset + 190] = make_dir_record(root_dir_lba, 0)
    iso_data[pvd_offset + 881] = 1 # File structure version
    
    # Root directory extent: "." and ".." records
    rd_offset = root_dir_lba * sector_size
    iso_data[rd_offset : rd_offset + 34] = make_dir_record(root_dir_lba, 0)
    iso_data[rd_offset + 34 : rd_offset + 68] = make_dir_record(root_dir_lba, 1)
    
    # 2. Boot Record Volume Descriptor (Sector 17)
    brvd_offset = 17 * sector_size
    iso_data[brvd_offset] = 0 # Type
    iso_data[brvd_offset + 1 : brvd_offset + 6] = b"CD001"
    iso_data[brvd_offset + 6] = 1 # Version
    iso_data[brvd_offset + 7 : brvd_offset + 39] = b"EL TORITO SPECIFICATION         "
    # Pointer to Boot Catalog (Sector 19)
    iso_data[brvd_offset + 71 : brvd_offset + 75] = struct.pack("<I", 19)
    
    # 3. Volume Descriptor Set Terminator (Sector 18)
    vdst_offset = 18 * sector_size
    iso_data[vdst_offset] = 255
    iso_data[vdst_offset + 1 : vdst_offset + 6] = b"CD001"
    iso_data[vdst_offset + 6] = 1
    
    # 4. Boot Catalog (Sector 19)
    bc_offset = 19 * sector_size
    # Validation Entry
    iso_data[bc_offset] = 1 # Header ID
    iso_data[bc_offset + 1] = 0xEF # Platform ID (UEFI)
    iso_data[bc_offset + 30] = 0x55 # Key byte 1
    iso_data[bc_offset + 31] = 0xAA # Key byte 2
    # Checksum: all 16-bit words of the validation entry must sum to 0 mod 0x10000
    words = struct.unpack("<16H", iso_data[bc_offset : bc_offset + 32])
    checksum = (-sum(words)) & 0xFFFF
    iso_data[bc_offset + 28 : bc_offset + 30] = struct.pack("<H", checksum)
    # Default Entry (points to efi_part.img)
    # Sector count is in 512-byte units. For a 256MB FAT image the 16-bit
    # field cannot describe the whole volume. Write 1 so EDK2/OVMF maps the
    # entire CD as BlockIo; the bootloader then reads FAT from ISO LBA 21.
    boot_sectors_512 = len(efi_data) // 512
    if boot_sectors_512 > 0xFFFF:
        boot_sectors_512 = 1
    if boot_sectors_512 < 1:
        boot_sectors_512 = 1
    iso_data[bc_offset + 32] = 0x88 # Bootable flag
    iso_data[bc_offset + 33] = 0x00 # Boot media type (0 = no emulation)
    iso_data[bc_offset + 34 : bc_offset + 36] = struct.pack("<H", 0) # Load segment (0)
    iso_data[bc_offset + 36] = 0 # System type
    iso_data[bc_offset + 38 : bc_offset + 40] = struct.pack("<H", boot_sectors_512) # Sector count
    iso_data[bc_offset + 40 : bc_offset + 44] = struct.pack("<I", boot_image_lba) # LBA of boot image
    
    # Assemble final ISO
    final_iso = iso_data + efi_data
    
    with open(iso_path, "wb") as f:
        f.write(final_iso)
    print(f"ISO successfully built: {iso_path} ({len(final_iso)} bytes)")

if __name__ == "__main__":
    # Create iso_root directories
    os.makedirs("iso_root/EFI/BOOT", exist_ok=True)
    
    # Copy OS loader
    if os.path.exists("build/BOOTX64.EFI"):
        import shutil
        shutil.copy2("build/BOOTX64.EFI", "iso_root/EFI/BOOT/BOOTX64.EFI")
    
    # Copy static assets
    if os.path.exists("frontend/static"):
        for root, dirs, files in os.walk("frontend/static"):
            for file in files:
                src = os.path.join(root, file)
                rel = os.path.relpath(src, "frontend/static")
                dst = os.path.join("iso_root", rel)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(src, dst)
                
    make_fat16_image("build/efi_part.img", "iso_root", size_mb=256)
    iso_path = "build/24scope.iso"
    try:
        os.remove(iso_path)
    except (FileNotFoundError, PermissionError):
        pass
    make_bootable_iso(iso_path, "build/efi_part.img")
