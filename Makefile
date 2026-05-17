BUILD_DIR = build
ROOTFS = $(BUILD_DIR)/rootfs
INITRAMFS = $(BUILD_DIR)/initrd.img

all: initramfs

initramfs: $(INITRAMFS)

$(INITRAMFS): $(ROOTFS)

$(ROOTFS):
.PHONY: all initramfs
