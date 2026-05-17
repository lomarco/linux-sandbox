BUILD_DIR = build
ROOTFS = $(BUILD_DIR)/rootfs
INITRAMFS = $(BUILD_DIR)/initrd.img

BUSYBOX = $(BUILD_DIR)/busybox
BUSYBOX_URL = https://busybox.net/downloads/binaries/1.35.0-x86\_64-linux-musl/busybox

LINUX = $(BUILD_DIR)/linux
LINUX_URL = https://www.kernel.org/pub/linux/kernel/v7.x/linux-7.0.8.tar.xz

all: initramfs

initramfs: $(INITRAMFS)
$(INITRAMFS): $(ROOTFS)
	;

rootfs: $(ROOTFS)
$(ROOTFS): busybox linux
	;

busybox: $(BUSYBOX)
$(BUSYBOX):
	;

linux: $(LINUX)
$(LINUX):
	;

.PHONY: all initramfs rootfs busybox linux
