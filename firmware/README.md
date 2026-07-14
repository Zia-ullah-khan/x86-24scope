# Intel iwlwifi firmware for x86-24scope

Place a Linux Intel WiFi firmware blob in this directory before running
`make_metal_usb.bat`. The OS looks for (in order):

1. `\EFI\FIRMWARE\IWLWIFI.UC`
2. `\EFI\FIRMWARE\IWLWIFI.UCODE`
3. `\EFI\FIRMWARE\FW.UC`

## How to get firmware

From a Linux install or the linux-firmware package, copy the file that matches
your PCI ID, for example:

- AX211 / many Meteor Lake: `iwlwifi-so-a0-gf-a0-89.ucode` (version may vary)
- AX210: `iwlwifi-ty-a0-gf-a0-*.ucode` or `iwlwifi-so-a0-gf-a0-*.ucode`
- AX200: `iwlwifi-cc-a0-*.ucode`

Rename or copy it to `IWLWIFI.UC` in this folder.

The file must be a Linux **TLV** `.ucode` (starts with `00 00 00 00` + `IWL\\n`). The OS skips the
88-byte TLV header and loads `SEC_RT` / related sections.

## Credentials

On boot the OS prompts for **SSID** and **Password** (keyboard or serial).
You do not need to edit `wifi_config.asm` for normal use.
