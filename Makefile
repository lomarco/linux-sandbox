BUILD_DIR = build
ROOTFS = $(BUILD_DIR)/rootfs
INITRAMFS = $(BUILD_DIR)/initrd.img

BUSYBOX = $(BUILD_DIR)/busybox
BUSYBOX_URL = https://busybox.net/downloads/binaries/1.35.0-x86\_64-linux-musl/busybox

LINUX = $(BUILD_DIR)/linux
LINUX_DIR = $(BUILD_DIR)/linux
LINUX_URL = https://www.kernel.org/pub/linux/kernel/v7.x/linux-7.0.8.tar.xz
LINUX_TEMP = $(LINUX_DIR)-temp

all: initramfs

initramfs: $(INITRAMFS)
$(INITRAMFS): $(BUILD_DIR) rootfs
	;

$(BUILD_DIR):
	mkdir $@

rootfs: $(ROOTFS)
$(ROOTFS): busybox linux
	;

busybox: $(BUSYBOX)
$(BUSYBOX):
	curl -fSLo $@ $(BUSYBOX_URL)

linux: $(LINUX)
$(LINUX):
	;
$(LINUX_DIR): $(LINUX_TEMP)
	tar -xJvf $(LINUX_TEMP) -C $@

$(LINUX_TEMP):
	curl -fSLo $(LINUX_TEMP) $(LINUX_URL)

$(LINUX_DIR):
	curl -fSLo $(LINUX_TEMP) $(LINUX_URL) \
	tar -xjvf $(LINUX_TEMP) -C $@ \
	rm -rf $(LINUX_TEMP)

.PHONY: all initramfs rootfs busybox linux
