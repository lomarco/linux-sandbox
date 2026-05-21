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

QEMU := qemu-system-x86_64
QEMU_OPTS := -m 512M \
						 -initrd $(INITRD) \
						 -kernel $(BZIMAGE) \
						 -append "console=ttyS0" \
						 -enable-kvm \
						 -serial mon:stdio

JOBS ?= $(shell nproc)

all: initrd

rebuild: clean all

run:
	$(QEMU) $(QEMU_OPTS)

$(BUILD_DIR) $(CACHE_DIR):
	mkdir -p $@

$(BUSYBOX): | $(CACHE_DIR)
	curl -fSLo $@ $(BUSYBOX_URL)
	chmod +x $@

busybox: $(BUSYBOX)

busybox-reinstall: clean-busybox $(BUSYBOX)

$(LINUX_TARBALL): | $(CACHE_DIR)
	curl -fSLo $@ $(LINUX_URL)

$(LINUX_DIR): $(LINUX_TARBALL) | $(BUILD_DIR)
	rm -rf $@
	mkdir -p $@
	tar -xJf $< -C $@ --strip-components=1

$(LINUX_CONFIG): $(LINUX_DIR)
	$(MAKE) -C $(LINUX_DIR) tinyconfig
	$(LINUX_DIR)/scripts/config --file $@ \
		--enable TTY \
		--set-str INITRAMFS_SOURCE "$(ROOTFS)"

$(BZIMAGE): $(LINUX_CONFIG)
	$(MAKE) -C $(LINUX_DIR) -j$(JOBS)

linux: $(BZIMAGE)

linux-rebuild: clean-linux $(BZIMAGE)

linux-reinstall: clean-linux-tar clean-linux-build $(LINUX_TARBALL)

$(ROOTFS): $(BUSYBOX) | $(BUILD_DIR)
	rm -rf $@
	mkdir -p $@/{bin,etc,proc,sys,dev,tmp,mnt,root}
	$(BUSYBOX) --install $@/bin
	ln -sf /bin/init $@/init
	if [ -d $(OVERLAYFS) ]; then cp -a $(OVERLAYFS)/. $@/; fi

rootfs: $(ROOTFS)

$(INITRD): $(ROOTFS) $(BZIMAGE) | $(BUILD_DIR)
	cd $(ROOTFS) && \
		find . -print0 | LC_ALL=C sort -z | \
		cpio --null -o --format=newc --owner=root:root | \
		gzip -9 -n > $@

initrd: $(INITRD)

clean:
	rm -rf $(BUILD_DIR)

clean-cache:
	rm -rf $(CACHE_DIR)

clean-linux:
	$(MAKE) -C $(LINUX_DIR) clean

clean-linux-dir:
	rm -rf $(LINUX_DIR)

clean-linux-tar:
	rm -f $(LINUX_TARBALL)

clean-busybox:
	rm -f $(BUSYBOX)

clean-initrd:
	rm -rf $(ROOTFS)
	rm -f $(INITRD)

wipe: clean clean-cache

help:
	@printf '%s\n' \
	'Usage: make [target]' \
	'' \
	'Targets:' \
	'  initrd               Build initrd image' \
	'  rootfs               Prepare rootfs' \
	'  rebuild              Clean and build' \
	'  busybox              Download BusyBox to cache' \
	'  busybox-reinstall    Redownload BusyBox' \
	'  linux                Build Linux kernel' \
	'  linux-reinstall      Redownload and rebuild Linux from scratch' \
	'  linux-rebuild        Rebuild Linux in existing tree' \
	'  run                  Boot QEMU' \
	'' \
	'  clean              Remove build artifacts' \
	'  clean-cache        Remove cache' \
	'  clean-linux        Execute `make clean` into build/linux' \
	'  clean-linux-dir    Remove linux dir' \
	'  clean-linux-tar    Remove installed linux tarball' \
	'  clean-busybox      Remove busybox from cache' \
	'  clean-initrd       Remove initrd from build' \
	'  wipe               Wipe all'

.PHONY: all run help clean clean-cache clean-linux clean-linux-dir clean-linux-tar clean-busybox clean-initrd wipe rebuild busybox busybox-reinstall linux linux-reinstall linux-rebuild rootfs initrd
