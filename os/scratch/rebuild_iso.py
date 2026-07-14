import os, shutil, sys
sys.path.insert(0, "os/scratch")
stage = "build/iso_stage"
if os.path.exists(stage):
    shutil.rmtree(stage, ignore_errors=True)

def ignore(dirpath, names):
    if dirpath.replace("\\", "/").endswith("EFI/BOOT"):
        return [n for n in names if n.upper().startswith("BOOTX64")]
    return []

shutil.copytree("iso_root", stage, ignore=ignore)
os.makedirs(os.path.join(stage, "EFI", "BOOT"), exist_ok=True)
shutil.copy2("build/BOOTX64.EFI", os.path.join(stage, "EFI", "BOOT", "BOOTX64.EFI"))
from make_uefi_image import make_fat16_image, make_bootable_iso
for f in ["build/efi_part.img", "build/24scope.iso"]:
    try:
        os.remove(f)
    except OSError:
        pass
make_fat16_image("build/efi_part.img", stage, size_mb=256)
make_bootable_iso("build/24scope.iso", "build/efi_part.img")
print("ISO ready")
