# x86-24scope

A low-level x86-64 assembly web application duplicate of 24Spy. Built entirely in raw assembly, serving custom HTML/JS frontend interfaces and querying live REST endpoints.

## Features

- **Frontend Server**: High-performance HTTP server written in x86-64 assembly, serving static pages, aircraft assets, and maps on port `8091`.
- **Backend Status Server**: Multi-platform listener on port `8080` that checks downstream availability of 24data REST controllers using WinInet (Windows) or libcurl (Linux/macOS).
- **Zero-Dependency Core**: Only links standard system socket APIs and networking libraries.

## Supported Operating Systems

- **Windows** (x86-64)
- **Linux** (x86-64)
- **macOS** (x86-64 / Apple Silicon via Rosetta 2)

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

All web routing, file handling, string conversion, and network protocols are processed in raw assembly registers and memory buffers. Conditional compilation macros (`LINUX`, `MACOS`, `WINDOWS`) are used to select the correct OS calling convention (Windows x64 vs System V AMD64) and system-level interface wrapper.