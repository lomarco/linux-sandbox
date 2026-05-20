.SHELLFLAGS := -euo pipefail -c

BUILD_DIR  := $(abspath build)
CACHE_DIR  := $(abspath cache)
OVERLAYFS  := $(abspath overlayfs)

ROOTFS      := $(BUILD_DIR)/rootfs
INITRAMFS   := $(BUILD_DIR)/initrd.img

BUSYBOX     := $(CACHE_DIR)/busybox
BUSYBOX_URL := https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox

LINUX_TARBALL := $(CACHE_DIR)/linux.tar.xz
LINUX_URL     := https://www.kernel.org/pub/linux/kernel/v7.x/linux-7.0.8.tar.xz

LINUX_DIR    := $(BUILD_DIR)/linux
LINUX_STAMP  := $(LINUX_DIR)/.unpacked
LINUX_CONFIG := $(LINUX_DIR)/.config
BZIMAGE      := $(LINUX_DIR)/arch/x86/boot/bzImage

ROOTFS_STAMP := $(ROOTFS)/.prepared

QEMU := qemu-system-x86_64
QEMU_OPTS := -m 512M \
						 -initrd $(INITRAMFS) \
						 -kernel $(BZIMAGE) \
						 -append "console=ttyS0" \
						 -enable-kvm \
						 -serial mon:stdio

all: initramfs

rebuild: clean all

run: initramfs
	$(QEMU) $(QEMU_OPTS)

$(BUILD_DIR) $(CACHE_DIR):
	mkdir -p $@

$(BUSYBOX): | $(CACHE_DIR)
	curl -fSLo $@ $(BUSYBOX_URL)
	chmod +x $@

busybox: $(BUSYBOX)

busybox-reinstall: | $(CACHE_DIR)
	curl -fSLo $(BUSYBOX) $(BUSYBOX_URL)
	chmod +x $(BUSYBOX)
	rm -f $(BUSYBOX_INSTALL)

linux: $(BZIMAGE)

linux-reinstall: | $(CACHE_DIR)
	curl -fSLo $(LINUX_TARBALL) $(LINUX_URL)
	rm -rf $(LINUX_DIR)
	mkdir -p $(LINUX_DIR)
	tar -xJf $(LINUX_TARBALL) -C $(LINUX_DIR) --strip-components=1
	$(MAKE) -C $(LINUX_DIR) tinyconfig
	$(MAKE) -C $(LINUX_DIR) -j$$(nproc) 2>&1 | tee build-kernel.log
	touch $(LINUX_UNPACK_STAMP)

linux-rebuild: $(LINUX_UNPACK_STAMP)
	$(MAKE) -C $(LINUX_DIR) -j$$(nproc) 2>&1 | tee build-kernel.log

$(LINUX_UNPACK_STAMP): $(LINUX_TARBALL) | $(BUILD_DIR)
	rm -rf $(LINUX_DIR)
	mkdir -p $(LINUX_DIR)
	tar -xJf $< -C $(LINUX_DIR) --strip-components=1
	touch $@

$(LINUX_CONFIG): $(LINUX_STAMP)
	$(MAKE) -C $(LINUX_DIR) tinyconfig
	$(LINUX_DIR)/scripts/config --file $@ \
		--enable TTY \
		--set-str INITRAMFS_SOURCE "$(ROOTFS)"
	touch $@

$(ROOTFS)/$(OVERLAYFS):
	cp -r $(OVERLAYFS)/* $(ROOTFS)

rootfs: $(ROOTFS_INIT)

linux-rebuild: $(LINUX_STAMP)
	$(LINUX_DIR)/scripts/config --file $(LINUX_CONFIG) \
		--set-str INITRAMFS_SOURCE "$(ROOTFS)"
	$(MAKE) -C $(LINUX_DIR) -j$(JOBS)

linux-reinstall: | $(CACHE_DIR)
	curl -fL --retry 3 --retry-delay 1 -o $(LINUX_TARBALL) $(LINUX_URL)
	rm -rf $(LINUX_DIR)
	$(MAKE) $(BZIMAGE)

$(ROOTFS_STAMP): $(BUSYBOX) | $(BUILD_DIR)
	rm -rf $(ROOTFS)
	mkdir -p $(ROOTFS)/{bin,etc,proc,sys,dev,tmp,mnt,root}
	$(BUSYBOX) --install $(ROOTFS)/bin
	ln -sf /bin/init $(ROOTFS)/init
	if [ -d $(OVERLAYFS) ]; then cp -a $(OVERLAYFS)/. $(ROOTFS)/; fi
	touch $@

rootfs: $(ROOTFS_STAMP)

$(INITRAMFS): $(ROOTFS_STAMP) $(BZIMAGE) | $(BUILD_DIR)
	cd $(ROOTFS) && \
		find . -print0 | LC_ALL=C sort -z | \
		cpio --null -o --format=newc --owner=root:root > $@

initramfs: $(INITRAMFS)

clean:
	rm -rf $(BUILD_DIR)

distclean: clean
	rm -rf $(CACHE_DIR)

help:
	@printf '%s\n' \
	'Usage: make [target]' \
	'' \
	'Targets:' \
	'  all               Build initramfs (default)' \
	'  initramfs         Build initramfs image' \
	'  rootfs            Prepare rootfs' \
	'  busybox           Download BusyBox to cache' \
	'  busybox-reinstall Redownload BusyBox' \
	'  linux             Build Linux kernel' \
	'  linux-reinstall   Redownload and rebuild Linux from scratch' \
	'  linux-rebuild     Rebuild Linux in existing tree' \
	'  run               Boot QEMU' \
	'  clean             Remove build artifacts' \
	'  distclean         Remove build artifacts and cache'

.PHONY: all run help clean distclean rebuild busybox busybox-reinstall linux linux-reinstall linux-rebuild rootfs initramfs
