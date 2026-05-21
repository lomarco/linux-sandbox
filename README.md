# Linux sandbox

## About
Linux Sandbox is a minimal environment for experimenting with the Linux kernel and userspace. It provides fast, reproducible builds and boots QEMU with a customizable rootfs filesystem.

## Quick start
To begin using Linux Sandbox, run:
```bash
make
```
This will download required files and build the kernel and initramfs.

If you modified the kernel source and need to rebuild only the kernel, run:
```bash
make linux-rebuild
```

To boot the built image in QEMU, run:
```bash
make run
```

The rest you can look at `make help`.

## Dependencies
- bash >=4
- make >=4.0
- curl >=7.50.0
- tar (GNU tar) >=1.28
- xz-utils (xz) >=5.2
- coreutils >=8.25
- cpio >=2.12
- gcc >=10
- binutils >=2.30
- libncurses-dev >=6.1
- bc >=1.07
- perl >=5.20
- python3 >=3.6
- pkg-config >=0.29
- qemu-system-x86_64 >=6.0
