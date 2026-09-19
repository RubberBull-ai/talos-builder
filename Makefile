# siderolabs/pkgs has no v1.14.1 tag: Talos v1.14.1 is built against pkgs
# v1.14.0-25-gf694e1b (pkg/machinery/gendata/data/pkgs at talos tag v1.14.1),
# i.e. commit f694e1b on release-1.14. Pin that exact commit so our kernel
# carries the same patches (incl. the RP1/macb TX-stall fixes) as the
# upstream v1.14.1 kernel. `git describe` of it yields v1.14.0-25-gf694e1b.
PKG_VERSION = f694e1bfb5c5bedd69b030ef00e9784986e64de3
TALOS_VERSION = v1.14.1
# talos-rpi5 overlay fork: its U-Boot (talos-rpi5/u-boot v2025.04-rpi5-3) has
# the BCM2712 PCIe driver needed to boot from NVMe. The upstream
# siderolabs/sbc-raspberrypi rpi_5 overlay cannot (sbc-raspberrypi#81, #88).
SBCOVERLAY_VERSION = main

REGISTRY ?= ghcr.io
REGISTRY_USERNAME ?= talos-rpi5

TAG ?= $(shell git describe --tags --exact-match)

# Extension versions as shipped for Talos v1.14.1 (siderolabs/extensions v1.14.1)
EXTENSIONS_ISCSI ?= ghcr.io/siderolabs/iscsi-tools:v0.2.0
EXTENSIONS_TAILSCALE ?= ghcr.io/siderolabs/tailscale:1.102.3
EXTENSIONS_UTIL_LINUX ?= ghcr.io/siderolabs/util-linux-tools:2.42.2

PKG_REPOSITORY = https://github.com/siderolabs/pkgs.git
TALOS_REPOSITORY = https://github.com/siderolabs/talos.git
SBCOVERLAY_REPOSITORY = https://github.com/talos-rpi5/sbc-raspberrypi5.git

# Optional buildx registry layer cache (CI sets BUILD_CACHE=1). One ref per
# build target, independent of git tags, so re-runs of the same inputs
# (e.g. re-pushing a release tag) skip the unchanged stages.
BUILD_CACHE ?=
CACHE_REPOSITORY ?= $(REGISTRY)/$(REGISTRY_USERNAME)/talos-builder-cache
comma := ,
cache_args = $(if $(BUILD_CACHE),--cache-from=type=registry$(comma)ref=$(CACHE_REPOSITORY):$(1) --cache-to=type=registry$(comma)ref=$(CACHE_REPOSITORY):$(1)$(comma)mode=max$(comma)image-manifest=true$(comma)oci-mediatypes=true$(comma)ignore-error=true)

CHECKOUTS_DIRECTORY := $(PWD)/checkouts
PATCHES_DIRECTORY := $(PWD)/patches
PROFILES_DIRECTORY := $(PWD)/profiles

PKGS_TAG = $(shell cd $(CHECKOUTS_DIRECTORY)/pkgs && git describe --tag --always --dirty --match v[0-9]\*)
TALOS_TAG = $(shell cd $(CHECKOUTS_DIRECTORY)/talos && git describe --tag --always --dirty --match v[0-9]\*)
SBCOVERLAY_TAG = $(shell cd $(CHECKOUTS_DIRECTORY)/sbc-raspberrypi5 && git describe --tag --always --dirty)-$(PKGS_TAG)

#
# Help
#
.PHONY: help
help:
	@echo "checkouts : Clone repositories required for the build"
	@echo "patches   : Apply all patches"
	@echo "kernel    : Build kernel"
	@echo "overlay   : Build Raspberry Pi 5 overlay"
	@echo "installer : Build installer docker image and disk image"
	@echo "release   : Use only when building the final release, this will tag relevant images with the current Git tag."
	@echo "clean     : Clean up any remains"



#
# Checkouts
#
.PHONY: checkouts checkouts-clean
checkouts:
	git clone -c advice.detachedHead=false "$(PKG_REPOSITORY)" "$(CHECKOUTS_DIRECTORY)/pkgs"
	git -C "$(CHECKOUTS_DIRECTORY)/pkgs" -c advice.detachedHead=false checkout "$(PKG_VERSION)"
	git clone -c advice.detachedHead=false --branch "$(TALOS_VERSION)" "$(TALOS_REPOSITORY)" "$(CHECKOUTS_DIRECTORY)/talos"
	git clone -c advice.detachedHead=false --branch "$(SBCOVERLAY_VERSION)" "$(SBCOVERLAY_REPOSITORY)" "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi5"

checkouts-clean:
	rm -rf "$(CHECKOUTS_DIRECTORY)/pkgs"
	rm -rf "$(CHECKOUTS_DIRECTORY)/talos"
	rm -rf "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi5"



#
# Patches
#
.PHONY: patches-pkgs patches-talos patches
patches-pkgs:
	cd "$(CHECKOUTS_DIRECTORY)/pkgs" && \
		git am --committer-date-is-author-date "$(PATCHES_DIRECTORY)/siderolabs/pkgs/0001-Patched-for-Raspberry-Pi-5.patch"

patches-talos:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		git am --committer-date-is-author-date "$(PATCHES_DIRECTORY)/siderolabs/talos/0001-Patched-for-Raspberry-Pi-5.patch" && \
		git am --committer-date-is-author-date "$(PATCHES_DIRECTORY)/siderolabs/talos/0002-Skip-NVRAM-writes-for-GRUB-on-arm64.patch" && \
		git am --committer-date-is-author-date "$(PATCHES_DIRECTORY)/siderolabs/talos/0003-Force-GRUB-bootloader-on-arm64.patch"

patches: patches-pkgs patches-talos



#
# Kernel
#
.PHONY: kernel
kernel:
	cd "$(CHECKOUTS_DIRECTORY)/pkgs" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) PUSH=true \
			PLATFORM=linux/arm64 \
			CI_ARGS="$(call cache_args,kernel)" \
			kernel



#
# Overlay
#
.PHONY: overlay
overlay:
	@echo SBCOVERLAY_TAG = $(SBCOVERLAY_TAG)
	cd "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi5" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) IMAGE_TAG=$(SBCOVERLAY_TAG) PUSH=true \
			PKGS_PREFIX=$(REGISTRY)/$(REGISTRY_USERNAME) PKGS=$(PKGS_TAG) \
			INSTALLER_ARCH=arm64 PLATFORM=linux/arm64 \
			CI_ARGS="$(call cache_args,overlay)" \
			sbc-raspberrypi5



#
# Installer/Image
#
.PHONY: installer
TALOS_MAKE = $(MAKE) \
	REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) PUSH=true \
	PKG_KERNEL=$(REGISTRY)/$(REGISTRY_USERNAME)/kernel:$(PKGS_TAG) \
	INSTALLER_ARCH=arm64 PLATFORM=linux/arm64 \
	IMAGER_ARGS="--overlay-name=rpi5 --overlay-image=$(REGISTRY)/$(REGISTRY_USERNAME)/sbc-raspberrypi5:$(SBCOVERLAY_TAG) --system-extension-image=$(EXTENSIONS_ISCSI) --system-extension-image=$(EXTENSIONS_TAILSCALE) --system-extension-image=$(EXTENSIONS_UTIL_LINUX)"

installer:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		$(TALOS_MAKE) CI_ARGS="$(call cache_args,talos-kernel)" kernel && \
		$(TALOS_MAKE) CI_ARGS="$(call cache_args,talos-initramfs)" initramfs && \
		$(TALOS_MAKE) CI_ARGS="$(call cache_args,talos-imager)" imager && \
		$(TALOS_MAKE) CI_ARGS="$(call cache_args,talos-installer-base)" installer-base && \
		$(TALOS_MAKE) installer && \
		sed \
			-e 's|__BASE_INSTALLER__|$(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TALOS_TAG)|' \
			-e 's|__OVERLAY_IMAGE__|$(REGISTRY)/$(REGISTRY_USERNAME)/sbc-raspberrypi5:$(SBCOVERLAY_TAG)|' \
			-e 's|__EXTENSIONS_ISCSI__|$(EXTENSIONS_ISCSI)|' \
			-e 's|__EXTENSIONS_TAILSCALE__|$(EXTENSIONS_TAILSCALE)|' \
			-e 's|__EXTENSIONS_UTIL_LINUX__|$(EXTENSIONS_UTIL_LINUX)|' \
			"$(PROFILES_DIRECTORY)/rpi5-metal.yaml" \
		| docker run --rm -i -v ./_out:/out -v /dev:/dev --privileged $(REGISTRY)/$(REGISTRY_USERNAME)/imager:$(TALOS_TAG) -



#
# Release
#
.PHONY: release
release:
	docker pull $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TALOS_TAG) && \
		docker tag $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TALOS_TAG) $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TAG) && \
		docker push $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TAG)



#
# Clean
#
.PHONY: clean
clean: checkouts-clean
