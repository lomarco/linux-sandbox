.SHELLFLAGS := -euo pipefail -c

BUILD_DIR  := $(abspath build)
CACHE_DIR  := $(abspath cache)
OVERLAYFS  := $(abspath overlayfs)

LINUX_VERSION := 7.0.8

ROOTFS := $(BUILD_DIR)/rootfs
INITRD := $(BUILD_DIR)/initrd.img

BUSYBOX     := $(CACHE_DIR)/busybox
BUSYBOX_URL := https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox

LINUX_TARBALL := $(CACHE_DIR)/linux.tar.xz
LINUX_URL     := https://www.kernel.org/pub/linux/kernel/v7.x/linux-$(LINUX_VERSION).tar.xz

LINUX_DIR    := $(BUILD_DIR)/linux
LINUX_CONFIG := $(LINUX_DIR)/.config
BZIMAGE      := $(LINUX_DIR)/arch/x86/boot/bzImage

LINUX_STAMP  := $(BUILD_DIR)/.linux-stamp
ROOTFS_STAMP := $(BUILD_DIR)/.rootfs-stamp

MEM := 28M
QEMU := qemu-system-x86_64
QEMU_OPTS := -m $(MEM) \
						 -initrd $(INITRD) \
						 -kernel $(BZIMAGE) \
						 -append "console=ttyS0" \
						 -enable-kvm \
						 -serial mon:stdio

JOBS ?= $(shell nproc)

all: linux rootfs initrd

rebuild: clean all

run:
	$(QEMU) $(QEMU_OPTS)

$(BUILD_DIR) $(CACHE_DIR) $(OVERLAYFS):
	mkdir -p $@

$(BUSYBOX): | $(CACHE_DIR)
	curl -fSLo $@ $(BUSYBOX_URL)
	chmod +x $@

busybox: $(BUSYBOX)

busybox-reinstall: clean-busybox $(BUSYBOX)

$(LINUX_TARBALL): | $(CACHE_DIR)
	curl -fSLo $@ $(LINUX_URL)

linux-extract: $(LINUX_DIR)

$(LINUX_DIR): $(LINUX_TARBALL) | $(BUILD_DIR)
	rm -rf $@
	mkdir -p $@
	tar -xJf $< -C $@ --strip-components=1

$(LINUX_CONFIG): | $(LINUX_DIR)
	$(MAKE) -C $(LINUX_DIR) tinyconfig
	$(LINUX_DIR)/scripts/config --file $(LINUX_CONFIG) \
		--set-val ARCH x86_64 \
		--enable CONFIG_64BIT \
		--enable CONFIG_TTY \
		--enable CONFIG_PRINTK \
		--enable CONFIG_BLK_DEV_INITRD \
		--enable CONFIG_DEVTMPFS \
		--enable CONFIG_PROC_FS \
		--enable CONFIG_SYSFS \
		--enable CONFIG_INITRAMFS_COMPRESSION_GZIP \
		--enable CONFIG_BINFMT_ELF \
		--enable CONFIG_BINFMT_SCRIPT \
		--enable CONFIG_SERIAL_CORE \
		--enable CONFIG_SERIAL_8250 \
		--enable CONFIG_SERIAL_8250_CONSOLE
	$(MAKE) -C $(LINUX_DIR) olddefconfig

$(BZIMAGE): $(LINUX_CONFIG) | $(LINUX_DIR)
	$(MAKE) -C $(LINUX_DIR) -j$(JOBS)
	touch $(LINUX_STAMP)

linux: $(BZIMAGE)

linux-rebuild: clean-linux linux

linux-reinstall: clean-linux-tar clean-linux-dir $(BZIMAGE)

$(ROOTFS): $(BUSYBOX) | $(BUILD_DIR)
	rm -rf $@
	mkdir -p $@/{bin,etc,proc,sys,dev,tmp,mnt,root,run}
	$(BUSYBOX) --install $@/bin
	ln -sf /bin/init $@/init
	if [ -d $(OVERLAYFS) ]; then \
		cp -a $(OVERLAYFS)/. $@/; \
	fi

$(ROOTFS_STAMP): $(ROOTFS)
	touch $@

rootfs: $(ROOTFS_STAMP)

$(INITRD): $(ROOTFS_STAMP) | $(BUILD_DIR)
	cd $(ROOTFS) && \
		find . -print0 | LC_ALL=C sort -z | \
		cpio --null -o --format=newc --owner=root:root | \
		gzip -9 -n > $@

initrd: $(INITRD)

initrd-rebuild: clean-initrd rootfs initrd

clean:
	rm -rf $(BUILD_DIR)
	rm -f $(LINUX_STAMP) $(ROOTFS_STAMP)

clean-cache:
	rm -rf $(CACHE_DIR)

clean-linux:
	$(MAKE) -C $(LINUX_DIR) clean
	rm -f $(LINUX_STAMP)

clean-linux-dir:
	rm -rf $(LINUX_DIR)
	rm -f $(LINUX_STAMP)

clean-linux-tar:
	rm -f $(LINUX_TARBALL)

clean-busybox:
	rm -f $(BUSYBOX)

clean-initrd:
	rm -rf $(ROOTFS)
	rm -f $(INITRD) $(ROOTFS_STAMP)

wipe: clean clean-cache

help:
	@printf '%s\n' \
		'Usage: make [target]' \
		'' \
		'Targets:' \
		'  all               Build everything: linux, rootfs and initrd' \
		'  initrd            Build initrd image from current rootfs' \
		'  initrd-rebuild    Clean and rebuild initrd (recreate rootfs then initrd)' \
		'  rootfs            Prepare minimal root filesystem using BusyBox' \
		'  linux             Build Linux kernel (bzImage)' \
		'  rebuild           Clean (all) and build everything' \
		'  run               Boot the built kernel+initrd under QEMU' \
		'  busybox           Download BusyBox binary into cache' \
		'  busybox-reinstall Redownload BusyBox (useful after clean-cache)' \
		'  linux-extract     Extract Linux tarball into build/linux' \
		'  linux-reinstall   Remove linux tar/dir and rebuild kernel from scratch' \
		'  linux-rebuild     Rebuild kernel in existing linux source tree' \
		'' \
		'  clean           Remove build artifacts (build dir and stamps)' \
		'  clean-cache     Remove cached downloads' \
		'  clean-linux     Run make clean inside linux tree and remove stamp' \
		'  clean-linux-dir Remove extracted linux source directory' \
		'  clean-linux-tar Remove downloaded linux tarball' \
		'  clean-busybox   Remove cached BusyBox binary' \
		'  clean-initrd    Remove generated rootfs and initrd artifacts' \
		'  wipe            Full cleanup: clean + clean-cache' \
		'' \
		'Variables:' \
		'  INITRD        Initrd path' \
		'  BZIMAGE       Linux Kernel path' \
		'  MEM           Memory for QEMU (e.g., 512M)' \
		'  JOBS          Parallel make jobs (default: nproc)' 
		'  LINUX_VERSION Version Linux kernel' 

.PHONY: all run help clean clean-cache clean-linux clean-linux-dir clean-linux-tar clean-busybox clean-initrd wipe rebuild busybox busybox-reinstall linux-extract linux linux-reinstall linux-rebuild rootfs initrd initrd-rebuild
