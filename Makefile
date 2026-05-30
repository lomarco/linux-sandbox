.SHELLFLAGS := -euo pipefail -c

BUILD_DIR  := $(abspath build)
CACHE_DIR  := $(abspath cache)
OVERLAYFS  := $(abspath overlayfs)
MODULES    := $(abspath modules)

LINUX_VERSION := 7.0.8
LINUX_REPO    := https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
LINUX_TAG     := v$(LINUX_VERSION)

ROOTFS := $(BUILD_DIR)/rootfs
INITRD := $(BUILD_DIR)/initrd.img

BUSYBOX     := $(CACHE_DIR)/busybox
BUSYBOX_URL := https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox

LINUX_DIR    := $(BUILD_DIR)/linux
LINUX_CONFIG := $(LINUX_DIR)/.config
BZIMAGE      := $(LINUX_DIR)/arch/x86/boot/bzImage

LINUX_CLONE_STAMP   := $(BUILD_DIR)/.linux-clone-stamp
LINUX_CONFIG_STAMP  := $(BUILD_DIR)/.linux-config-stamp
LINUX_BUILD_STAMP   := $(BUILD_DIR)/.linux-build-stamp
MODULES_STAMP       := $(BUILD_DIR)/.modules-stamp
ROOTFS_STAMP        := $(BUILD_DIR)/.rootfs-stamp
INITRD_STAMP        := $(BUILD_DIR)/.initrd-stamp

MEM := 28M
QEMU := qemu-system-x86_64
QEMU_OPTS := -m $(MEM) \
						 -initrd $(INITRD) \
						 -kernel $(BZIMAGE) \
						 -append "console=ttyS0" \
						 -enable-kvm \
						 -serial mon:stdio

JOBS ?= $(shell nproc)
LLVM ?=

.PHONY += all
all: linux modules rootfs initrd

.PHONY += rebuild
rebuild: clean all

.PHONY += run
run:
	$(QEMU) $(QEMU_OPTS)

$(BUILD_DIR) $(CACHE_DIR) $(OVERLAYFS):
	mkdir -p $@

$(BUSYBOX): | $(CACHE_DIR)
	curl -fSLo $@ $(BUSYBOX_URL)
	chmod +x $@

.PHONY += busybox
busybox: $(BUSYBOX)

.PHONY += busybox-reinstall
busybox-reinstall: clean-busybox $(BUSYBOX)

.PHONY += linux-extract
linux-extract: $(LINUX_CLONE_STAMP)

$(LINUX_CLONE_STAMP): | $(BUILD_DIR)
	rm -rf $(LINUX_DIR)
	git clone --depth 1 --branch $(LINUX_TAG) $(LINUX_REPO) $(LINUX_DIR)
	touch $@

$(LINUX_CONFIG): $(LINUX_CLONE_STAMP) | $(LINUX_DIR)
	$(MAKE) -C $(LINUX_DIR) LLVM=$(LLVM) tinyconfig
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
		--enable CONFIG_SERIAL_8250_CONSOLE \
		--enable CONFIG_MODULES \
		--enable CONFIG_MODULE_UNLOAD \
		--enable CONFIG_MODULES_TREE_VERSION \
		--enable CONFIG_MODULE_DEBUGFS \
		--enable CONFIG_MODULE_FORCE_LOAD \
		--enable CONFIG_MODULE_FORCE_UNLOAD \
		--enable CONFIG_MODULE_COMPRESS_GZIP \
		--enable CONFIG_MODULE_COMPRESS_XZ \
		--enable CONFIG_MODULE_COMPRESS_ZSTD \
		--enable CONFIG_MODULE_COMPRESS_ALL \
		--enable CONFIG_MODULE_DECOMPRESS \
		--enable CONFIG_MODULES_TREE_LOOKUP
	$(MAKE) -C $(LINUX_DIR) LLVM=$(LLVM) olddefconfig
	touch $@

$(BZIMAGE): $(LINUX_CONFIG) | $(LINUX_DIR)
	$(MAKE) -C $(LINUX_DIR) LLVM=$(LLVM) -j$(JOBS)
	touch $(LINUX_BUILD_STAMP)

.PHONY += linux
linux: $(BZIMAGE)

.PHONY += linux-rebuild
linux-rebuild: clean-linux linux

.PHONY += linux-reinstall
linux-reinstall: clean-linux-dir $(BZIMAGE)

.PHONY += linux-update
linux-update: $(LINUX_CLONE_STAMP)
	cd $(LINUX_DIR) && git pull --rebase

.PHONY += modules-install
modules-install: $(LINUX_CONFIG) $(BZIMAGE) | $(ROOTFS)
	$(MAKE) -C $(LINUX_DIR) modules_prepare
	$(MAKE) -C $(LINUX_DIR) -j$(JOBS)
	$(MAKE) -C $(LINUX_DIR) M=$(MODULES) modules -j$(JOBS)
	$(MAKE) -C $(LINUX_DIR) INSTALL_MOD_PATH=$(ROOTFS) INSTALL_MOD_STRIP=1 modules_install
	$(MAKE) -C $(LINUX_DIR) M=$(MODULES) \
		INSTALL_MOD_PATH=$(ROOTFS) \
		INSTALL_MOD_DIR=extra \
		modules_install || true
	depmod -a -b $(ROOTFS) $(LINUX_VERSION) || true
	touch $(MODULES_STAMP)

$(ROOTFS): $(BUSYBOX) | $(BUILD_DIR)
	rm -rf $@
	mkdir -p $@/{bin,etc,proc,sys,dev,tmp,mnt,root,run}
	$(BUSYBOX) --install $@/bin
	ln -sf /bin/init $@/init
	if [ -d $(OVERLAYFS) ]; then \
		cp -a $(OVERLAYFS)/. $@/; \
	fi
	touch $(ROOTFS_STAMP)

.PHONY += rootfs
rootfs: $(ROOTFS) modules-install

$(INITRD): rootfs | $(BUILD_DIR)
	cd $(ROOTFS) && \
		find . -print0 | LC_ALL=C sort -z | \
		cpio --null -o --format=newc --owner=root:root | \
		gzip -9 -n > $@
	touch $(INITRD_STAMP)

.PHONY += initrd
initrd: $(INITRD)

.PHONY += initrd-rebuild
initrd-rebuild: clean-initrd rootfs initrd

.PHONY += clean
clean:
	rm -rf $(BUILD_DIR)
	rm -f $(LINUX_BUILD_STAMP) $(ROOTFS_STAMP) $(MODULES_STAMP) \
	       $(LINUX_CLONE_STAMP) $(LINUX_CONFIG_STAMP) $(LINUX_CONFIG)

.PHONY += clean-cache
clean-cache:
	rm -rf $(CACHE_DIR)

.PHONY += clean-linux
clean-linux:
	$(MAKE) -C $(LINUX_DIR) clean || true
	rm -f $(LINUX_BUILD_STAMP)

.PHONY += clean-linux-dir
clean-linux-dir:
	rm -rf $(LINUX_DIR)
	rm -f $(LINUX_CLONE_STAMP) $(LINUX_CONFIG_STAMP) $(LINUX_CONFIG) $(LINUX_BUILD_STAMP)

.PHONY += clean-busybox
clean-busybox:
	rm -f $(BUSYBOX)

.PHONY += clean-initrd
clean-initrd:
	rm -rf $(ROOTFS)
	rm -f $(INITRD) $(ROOTFS_STAMP) $(INITRD_STAMP)

.PHONY += clean-modules
clean-modules:
	$(MAKE) -C $(LINUX_DIR) M=$(MODULES) clean || true
	rm -f $(MODULES_STAMP)

.PHONY += wipe
wipe: clean clean-cache

.PHONY += help
help:
	@printf '%s\n' \
		'Usage: make [target]' \
		'' \
		'Targets:' \
		'  all                  Build everything: linux, modules, rootfs and initrd' \
		'  initrd               Build initrd image from current rootfs' \
		'  initrd-rebuild       Clean and rebuild initrd (recreate rootfs then initrd)' \
		'  rootfs               Prepare minimal root filesystem using BusyBox + modules' \
		'  linux                Build Linux kernel (bzImage)' \
		'  modules              Build and install kernel modules into rootfs' \
		'  rebuild              Clean (all) and build everything' \
		'  run                  Boot the built kernel+initrd under QEMU' \
		'  busybox              Download BusyBox binary into cache' \
		'  busybox-reinstall    Redownload BusyBox (useful after clean-cache)' \
		'  linux-extract        Clone Linux repo via git into build/linux' \
		'  linux-update         Pull latest changes in existing git clone' \
		'  linux-reinstall      Remove linux dir and rebuild kernel from scratch' \
		'  linux-rebuild        Rebuild kernel in existing linux source tree' \
		'' \
		'  clean              Remove build artifacts (build dir and stamps)' \
		'  clean-cache        Remove cached downloads' \
		'  clean-linux        Run make clean inside linux tree and remove stamp' \
		'  clean-linux-dir    Remove extracted linux source directory' \
		'  clean-busybox      Remove cached BusyBox binary' \
		'  clean-initrd       Remove generated rootfs and initrd artifacts' \
		'  clean-modules      Clean built modules' \
		'  wipe               Full cleanup: clean + clean-cache' \
		'' \
		'Variables:' \
		'  INITRD           Initrd path' \
		'  BZIMAGE          Linux Kernel path' \
		'  MEM              Memory for QEMU (e.g., 512M)' \
		'  JOBS             Parallel make jobs (default: nproc)' \
		'  LINUX_VERSION    Version Linux kernel' \
		'  LINUX_REPO       Git repo URL for Linux kernel' \
		'  LINUX_TAG        Git tag/branch for Linux kernel' \
		'  LLVM             Use llvm project instead default compiler' \
		'' \
		'Module structure:' \
		'  modules/' \
		'    Kbuild           # Main kbuild file: obj-m += mod1.o mod2.o' \
		'    mod1.c           # Module source' \
		'    mod2.c           # Another module' \
		'' \
		'  Or per-module directories:' \
		'  modules/mod1/' \
		'    Kbuild           # obj-m += mod1.o' \
		'    mod1.c'
