# Python script to patch a GoLink-linked PE64 executable's Subsystem to 10 (EFI Application).
import sys
import struct

def patch_efi(filepath):
    print(f"Patching {filepath} to EFI Subsystem...")
    try:
        with open(filepath, 'r+b') as f:
            # Read MZ header signature
            mz_sig = f.read(2)
            if mz_sig != b'MZ':
                print("Error: Not a valid MZ executable.")
                return False
            
            # Read PE header offset at 0x3C
            f.seek(0x3C)
            pe_offset_bytes = f.read(4)
            pe_offset = struct.unpack('<I', pe_offset_bytes)[0]
            
            # Check PE signature
            f.seek(pe_offset)
            pe_sig = f.read(4)
            if pe_sig != b'PE\0\0':
                print("Error: Not a valid PE executable.")
                return False
            
            # Subsystem offset is at pe_offset + 4 (signature) + 20 (COFF header) + 68 (Optional header offset to Subsystem)
            # Total = pe_offset + 92
            subsystem_offset = pe_offset + 92
            f.seek(subsystem_offset)
            
            # Read current subsystem
            curr_subsystem = struct.unpack('<H', f.read(2))[0]
            print(f"Current Subsystem: {curr_subsystem}")
            
            # Write new subsystem: 10 (EFI Application)
            f.seek(subsystem_offset)
            f.write(struct.pack('<H', 10))
            print("Successfully patched Subsystem to 10 (EFI Application).")
            return True
            
    except Exception as e:
        print(f"Error patching file: {e}")
        return False

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python patch_efi.py <path_to_efi>")
    else:
        patch_efi(sys.argv[1])
