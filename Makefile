BUILD_DIR := build
CACHE_DIR := cache

ROOTFS := $(BUILD_DIR)/rootfs
INITRAMFS := $(BUILD_DIR)/initrd.img

BUSYBOX := $(CACHE_DIR)/busybox
BUSYBOX_URL := https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox

LINUX_TARBALL := $(CACHE_DIR)/linux.tar.xz
LINUX_URL := https://www.kernel.org/pub/linux/kernel/v7.x/linux-7.0.8.tar.xz

LINUX_DIR := $(BUILD_DIR)/linux
LINUX_UNPACK_STAMP := $(LINUX_DIR)/.unpacked
BZIMAGE := $(LINUX_DIR)/arch/x86/boot/bzImage
VMLINUX := $(BUILD_DIR)/vmlinuz

BUSYBOX_INSTALL := $(ROOTFS)/.busybox-installed
ROOTFS_INIT := $(ROOTFS)/.prepared

QEMU := qemu-system-x86_64
QEMU_OPTS := -m 512M \
						 -nographic \
						 -kernel $(VMLINUX) \
						 -initrd $(INITRAMFS) \
						 -append "console=ttyS0 root=/dev/ram0 rw" \
						 -enable-kvm

all: initramfs

run: initramfs
	$(QEMU) $(QEMU_OPTS)

$(BUILD_DIR) $(CACHE_DIR):
	mkdir -p $@

busybox: $(BUSYBOX)

$(BUSYBOX): | $(CACHE_DIR)
	curl -fSLo $@ $(BUSYBOX_URL)
	chmod +x $@

linux: $(VMLINUX)

$(VMLINUX): $(BZIMAGE)
	cp $< $@

$(LINUX_UNPACK_STAMP): $(LINUX_TARBALL) | $(BUILD_DIR)
	rm -rf $(LINUX_DIR)
	mkdir -p $(LINUX_DIR)
	tar -xJf $< -C $(LINUX_DIR) --strip-components=1
	touch $@

$(LINUX_TARBALL): | $(CACHE_DIR)
	curl -fSLo $@ $(LINUX_URL)

$(BZIMAGE): $(LINUX_UNPACK_STAMP)
	$(MAKE) -C $(LINUX_DIR) tinyconfig
	$(MAKE) -C $(LINUX_DIR) -j$$(nproc)

rootfs: $(ROOTFS_INIT)

$(ROOTFS_INIT): $(BUSYBOX) | $(BUILD_DIR)
	rm -rf $(ROOTFS)
	mkdir -p $(ROOTFS)/bin
	cp $(BUSYBOX) $(ROOTFS)/bin/busybox
	ln -sf /bin/busybox $(ROOTFS)/bin/sh
	touch $@

initramfs: $(INITRAMFS)

$(INITRAMFS): rootfs linux | $(BUILD_DIR)
	find $(ROOTFS) -print0 | LC_ALL=C sort -z | cpio -0o --format=newc | gzip -9 > $(INITRAMFS)

clean:
	rm -rf $(BUILD_DIR)

distclean: clean
	rm -rf $(CACHE_DIR)

help:
	@echo -e 'Usage: make [target]' \
	'\n' \
	'Targets:\n' \
	'  all         Build initramfs (default)\n' \
	'  initramfs   Build initramfs image\n' \
	'  rootfs      Prepare rootfs\n' \
	'  busybox     Download BusyBox to cache\n' \
	'  linux       Build Linux kernel and copy vmlinuz\n' \
	'  clean       Remove build artifacts only\n' \
	'  distclean   Remove build artifacts and cache\n' \
	'\n' \
	'  run   Start qemu with the built kernel and initramfs'

.PHONY: all help clean distclean initramfs rootfs busybox linux
