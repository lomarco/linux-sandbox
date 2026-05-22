.SHELLFLAGS := -euo pipefail -c

BUILD_DIR  := $(abspath build)
CACHE_DIR  := $(abspath cache)
OVERLAYFS  := $(abspath overlayfs)

ROOTFS := $(BUILD_DIR)/rootfs
INITRD := $(BUILD_DIR)/initrd.img

BUSYBOX     := $(CACHE_DIR)/busybox
BUSYBOX_URL := https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox

LINUX_TARBALL := $(CACHE_DIR)/linux.tar.xz
LINUX_URL     := https://www.kernel.org/pub/linux/kernel/v7.x/linux-7.0.8.tar.xz

LINUX_DIR    := $(BUILD_DIR)/linux
LINUX_CONFIG := $(LINUX_DIR)/.config
BZIMAGE      := $(LINUX_DIR)/arch/x86/boot/bzImage

LINUX_STAMP  := $(BUILD_DIR)/.linux-stamp
ROOTFS_STAMP := $(BUILD_DIR)/.rootfs-stamp

MEM := 512M
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
		--enable TTY \
		--set-str INITRAMFS_SOURCE "$(ROOTFS)"

$(BZIMAGE): $(LINUX_CONFIG) | $(LINUX_DIR)
	$(MAKE) -C $(LINUX_DIR) -j$(JOBS)
	touch $(LINUX_STAMP)

linux: $(BZIMAGE)

linux-rebuild: clean-linux-dir linux

linux-reinstall: clean-linux-tar clean-linux-dir $(BZIMAGE)

$(ROOTFS): $(BUSYBOX) | $(BUILD_DIR)
	rm -rf $@
	mkdir -p $@/{bin,etc,proc,sys,dev,tmp,mnt,root}
	$(BUSYBOX) --install $@/bin
	ln -sf /bin/init $@/init
	if [ -d $(OVERLAYFS) ]; then \
		cp -a $(OVERLAYFS)/. $@/; \
	fi
	touch $(ROOTFS_STAMP)

rootfs: $(ROOTFS)

$(INITRD): $(ROOTFS_STAMP) | $(BUILD_DIR) $(ROOTFS)
	cd $(ROOTFS) && \
		find . -print0 | LC_ALL=C sort -z | \
		cpio --null -o --format=newc --owner=root:root | \
		gzip -9 -n > $@

initrd: $(INITRD)

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
		'  all               Build everything' \
		'  initrd            Build initrd image' \
		'  rootfs            Prepare rootfs' \
		'  linux             Build Linux kernel' \
		'  rebuild           Clean and build' \
		'  run               Boot QEMU' \
		'  busybox           Download BusyBox to cache' \
		'  busybox-reinstall Redownload BusyBox' \
		'  linux-extract     Extracting linux tar to build' \
		'  linux-reinstall   Redownload and rebuild Linux from scratch' \
		'  linux-rebuild     Rebuild Linux in existing tree' \
		'' \
		'Variables:' \
		'  INITRD  - Initrd path' \
		'  BZIMAGE - Linux Kernel path' \
		'  MEM - Memory count for QEMU'

.PHONY: all run help clean clean-cache clean-linux clean-linux-dir clean-linux-tar clean-busybox clean-initrd wipe rebuild busybox busybox-reinstall linux-extract linux linux-reinstall linux-rebuild rootfs initrd
