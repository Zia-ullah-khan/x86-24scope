# x86-24scope

24Scope is a raw x86-64 assembly project that combines a bootable bare-metal
OS with two small HTTP servers. The OS boots under UEFI, initializes the
kernel, memory, console, storage, and networking, then starts the web app.
One server serves the radar UI and static assets, and the other reports the
live status of the 24data controllers endpoint.

## Features

- **Landing page**: A custom index page with a direct link into the radar view.
- **Radar map UI**: A MapLibre-based map that shows aircraft, airports,
	waypoints, VORTACs, and regional boundaries. It also includes track labels,
	a selection panel, and a distance/bearing measurement tool.
- **Live aircraft data**: The radar view tries live feeds from
	`https://ws.awdevhardware.org/acft-data` and `https://24data.ptfs.app/acft-data`,
	then falls back to demo traffic if neither feed is available.
- **Static asset serving**: The frontend server serves map data and plane icon
	assets from the local `frontend/static` tree.
- **24data status server**: A separate listener checks
	`https://24data.ptfs.app/controllers` and returns an online/offline HTML
	status page.
- **Bare-metal OS**: A UEFI bootloader and kernel in `os/` bring up the
	framebuffer, memory managers, networking stack, and HTTP server before the
	application UI appears.
- **Cross-platform assembly**: Windows uses WinInet for the status check, while
	Linux and macOS use libcurl.

## Host Build Platforms

- **Windows** (x86-64) for building and running the desktop server binaries
- **Linux** (x86-64) for building and running the desktop server binaries
- **macOS** (x86-64 / Apple Silicon via Rosetta 2) for building and running the desktop server binaries

---

## Build & Run Instructions

### 1. Windows

#### Prerequisites
- [NASM](https://www.nasm.us/) (add to PATH)
- GoLink linker (provided in build context or from GoDevTool)

#### Build
```cmd
build.bat
```

#### Run
```cmd
run.bat
```
To stop, run `stop.bat`.

---

### 2. Linux & macOS

#### Prerequisites
- [NASM](https://www.nasm.us/)
- Standard build tools (`gcc` for Linux, `clang` for macOS)
- `libcurl` developer headers/libraries (e.g. `libcurl4-openssl-dev` on Debian/Ubuntu, or standard macOS curl lib)

#### Build
First, make scripts executable:
```bash
chmod +x build.sh run.sh stop.sh
```
Then run the build script:
```bash
./build.sh
```

#### Run
```bash
./run.sh
```
To stop the servers, run:
```bash
./stop.sh
```

---

## Architecture details

The host-side frontend server listens on port `8091` and routes `/` to the
landing page, `/radar` to the radar UI, and everything else under
`frontend/static` to local assets. The backend status server listens on port
`8080` and returns a simple online/offline page based on the upstream
controllers check.

The bare-metal OS build in `os/` produces a UEFI boot image (`BOOTX64.EFI`)
that starts in the bootloader, passes control to the kernel, and then launches
the same web server stack on real hardware or in emulation.

All routing, file handling, string conversion, and network protocol work is
done directly in assembly with conditional compilation for `LINUX`, `MACOS`,
and `WINDOWS`.