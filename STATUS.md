# talos-builder v1.12.12 (intermediate upgrade step)

Branch: `talos_v_1-12` (based on `talos_v_1-14-1` at 93b4786, so all the
v1.14.1 boot fixes below carry over). Release tag: `v1.12.12-rpi5`.

## Why

The Pis run custom v1.11.5 (`ghcr.io/upmkuhn/installer:v1.11.5.2`). The
v1.14.1 installer refuses them: `compatibility/talos114`
`MinimumHostUpgradeVersion = 1.12.0`. To keep the NVMe data the upgrade goes
**1.11.5 -> v1.12.12-rpi5 -> v1.14.1-rpi5**, both in place.

Checked in the Talos sources (the installer pre-flight compares only
major.minor.patch, the `-3-g...` suffix of our builds is ignored):

| installer | MinimumHostUpgradeVersion | MaximumHostDowngradeVersion (excl.) | host | ok |
|---|---|---|---|---|
| v1.12.12 (`talos112`) | 1.10.0 | 1.14.0 | 1.11.5 | yes |
| v1.14.1 (`talos114`) | 1.12.0 | 1.16.0 | 1.12.12 | yes |

Kubernetes support (not checked by the installer, but by config
validation / `upgrade-k8s`): Talos 1.12 = 1.30-1.35, Talos 1.14 = 1.32-1.37;
prod-on-prem runs 1.34 (talos repo `KUBERNETES_VERSION`), inside both.

## Versions

| Component | v1.12.12 (this branch) |
|-----------|------------------------|
| Talos | v1.12.12 |
| Pkgs | `5eb9201` (`v1.12.0-113-g5eb9201`, release-1.12) |
| Kernel | upstream 6.18.49 (gcc 15), macb TX-stall fixes 0001-0003 + PCI 0004 (no EEE backport) |
| SBC overlay / U-Boot | talos-rpi5/sbc-raspberrypi5 `main` + our patches 0001-0003 / talos-rpi5/u-boot v2025.04-rpi5-3 (as v1.14.1) |
| Bootloader | GRUB (forced on arm64) |
| iscsi-tools / tailscale / util-linux-tools | v0.2.0 / 1.94.2 / 2.41.4 (siderolabs/extensions v1.12.12) |

## Patches

- `pkgs/0001` (config-arm64): the v1.14.1 patch rebased onto pkgs 5eb9201.
  Three conflicts, all symbols upstream 1.14 had changed and the patch never
  touched: kept the 1.12 upstream values (`XEN_NETDEV_FRONTEND=y`,
  `HID_REDRAGON=y`, `HID_MULTITOUCH` off, `INFINIBAND=y`) plus the patch's
  own changes (`VMXNET3=y`, `HID_MICROSOFT=y`, `HID_MONTEREY=y`, IB
  USER_MAD/USER_ACCESS off). Every one of the 157 symbols the v1.14.1 patch
  changes has the same value here, and it changes nothing else.
  `make olddefconfig` on 6.18.49 (gcc 15) keeps RP1/MACB/PCIE_BRCMSTB/
  BCM2712_MIP/NVMe built in; it only moves toolchain-dependent symbols and
  16K-page consequences (as with v1.14.1).
- `talos/0001` (modules-arm64.txt): upstream v1.12.12 list with the same
  removals/additions as the v1.14.1 patch (+ `cdc-phonet.ko`, PHONET is on in
  1.12). Checked against the CI-built kernel, see below.
- `talos/0002`, `talos/0003`: unchanged logic, apply cleanly.
- Overlay patches: unchanged (same overlay/U-Boot sources as v1.14.1).

## Upgrade over the v1.11.5.2 disk layout

EFI (100 MiB vfat), BIOS, BOOT (xfs, GRUB), META, STATE, EPHEMERAL,
u-longhorn. In upgrade mode the v1.12.12 installer does not touch the
partition table (only checks it is GPT), probes GRUB on BOOT, writes the new
kernel/initramfs to the other BOOT slot, rewrites grub.cfg, runs
`grub-install --target=arm64-efi --removable --no-nvram` (patch 0002) into
EFI and then the overlay installer, which copies `firmware/boot` + `u-boot.bin`
+ `config.txt` into EFI. Partitions are found by label, so u-longhorn is
irrelevant. The overlay payload is ~3.3 MB (2.6 MB firmware/boot incl.
1.9 MB `overlays/`, 0.7 MB U-Boot, DTBs 80 KB each; measured on the v1.14.1
overlay image), plus GRUB's BOOTAA64.EFI: far below 100 MiB.

---

# talos-builder v1.14.1 Upgrade

Branch: `talos_v_1-14-1` (based on `talos_v_1-12-2`, see the v1.12.2 section below)

## Versions

| Component | v1.11.5.2 (running) | v1.12.2 branch | v1.14.1 (this branch) |
|-----------|---------------------|----------------|------------------------|
| Talos | v1.11.5 | v1.12.2 | **v1.14.1** |
| Pkgs | v1.11.0 | v1.12.0 | **f694e1b** (`v1.14.0-25-gf694e1b`) |
| Kernel | RPi fork `stable_20250428` (6.12.25) | upstream 6.17.7 | **upstream 6.18.51** |
| SBC overlay | talos-rpi5/sbc-raspberrypi5 `main` | siderolabs/sbc-raspberrypi v0.1.8 | **talos-rpi5/sbc-raspberrypi5 `main`** |
| U-Boot | talos-rpi5/u-boot v2025.04-rpi5-3 | siderolabs rpi_generic (no Pi 5 PCIe) | **talos-rpi5/u-boot v2025.04-rpi5-3** |
| Bootloader | GRUB (forced on arm64) | GRUB | GRUB |
| iscsi-tools | v0.2.0 | v0.2.0 | v0.2.0 |
| tailscale | 1.88.3 | 1.88.3 | **1.102.3** |
| util-linux-tools | 2.41.1 | 2.41.1 | **2.42.2** |

### Why pkgs is pinned to a commit

siderolabs/pkgs has no `v1.14.1` tag. Talos v1.14.1 is built against pkgs
`v1.14.0-25-gf694e1b` (`pkg/machinery/gendata/data/pkgs` at talos tag
v1.14.1), i.e. commit `f694e1bfb5c5bedd69b030ef00e9784986e64de3` on
`release-1.14`. `PKG_VERSION` pins that exact commit, so the kernel we build
has exactly the same source + patch set as the stock v1.14.1 kernel, and
`git describe` yields the same `v1.14.0-25-gf694e1b` (+1 commit for our patch).
`make checkouts` therefore clones pkgs and then `git checkout`s the ref
(`git clone --branch` cannot take a SHA).

Extension versions are the ones siderolabs/extensions v1.14.1 ships.

## Boot chain / NVMe

The Pis boot Talos from NVMe. That requires a U-Boot with a BCM2712 PCIe
driver. The official siderolabs `rpi_5` overlay U-Boot has none
(sbc-raspberrypi#81, PR #88 still unmerged), so the v1.12.2 branch's switch to
`siderolabs/sbc-raspberrypi` would have broken NVMe boot. It also mismatched
the overlay name (`rpi_5` in the Makefile vs `rpi5` in
`profiles/rpi5-metal.yaml`), which is the likely reason the v1.12.2 CI runs
failed at the disk-image step.

This branch goes back to the boot chain the running v1.11.5.2 uses:
`talos-rpi5/sbc-raspberrypi5@main` (U-Boot `talos-rpi5/u-boot
v2025.04-rpi5-3`, `rpi_5_defconfig` with `PCI_BRCMSTB` for bcm2712, NVMe,
RP1/MACB) + GRUB forced on arm64 (talos patches 0002/0003). The overlay
installer speaks the same stdin/YAML protocol in Talos 1.14 (only the Go API
gained a `context.Context`), so the v1.9.5-machinery overlay binary still works.

**Risk (untested on hardware, test on rpi-06 before rollout):**

- The overlay copies the DTBs from *our kernel* (`/dtb/broadcom/bcm2712*`).
  With v1.11.5.2 those were RPi-fork (downstream) DTBs; now they are mainline
  6.18 DTBs (`bcm2712-rpi-5-b.dtb`, `bcm2712-d-rpi-5-b.dtb`,
  `bcm2712-rpi-5-b-ovl-rp1.dtb`). U-Boot uses the firmware-provided DT, so
  its PCIe/NVMe driver now runs against the mainline DT. Mainline has
  `brcm,bcm2712-pcie` nodes + RP1, but this combination has not been booted.
- Mainline names the D0-stepping DT `bcm2712-d-rpi-5-b.dtb`; the firmware
  looks for `bcm2712d0-rpi-5-b.dtb`. D0 boards (2 GB/16 GB and newer 4/8 GB)
  will fall back to `bcm2712-rpi-5-b.dtb`. rpi-01..05 report
  `raspberrypi,5-model-b brcm,bcm2712` (C1, not affected); rpi-06's stepping
  is unknown. Not mitigated on purpose (owner decision): fix only if the
  rpi-06 test shows a problem. Obvious fix: ship the D0 DTB under both names
  (copy `bcm2712-d-rpi-5-b.dtb` to `bcm2712d0-rpi-5-b.dtb` in the overlay),
  or set `device_tree=bcm2712-d-rpi-5-b.dtb` via `configTxtAppend`.
- The fork overlay sets `console=ttyAMA0,115200`; with mainline DT the Pi 5
  debug UART is `ttyAMA10` (upstream overlay uses that). Serial console only.
- The firmware `overlays/` shipped by the fork are downstream `.dtbo`s
  (`disable-bt`, `disable-wifi` in config.txt); they may not apply cleanly to
  the mainline DT (firmware ignores failing overlays).

## Boot fixes after the rpi-06 hardware test (2026-09-19)

Tested on rpi-06 (Pi 5 Model B C1, NVMe HAT, PXE from 192.168.0.2). Boot
chain: EEPROM firmware -> config.txt + `bcm2712-rpi-5-b.dtb` -> `u-boot.bin`
-> NVMe, else network (pxelinux.cfg misses, then EFI net boot of
`vmlinuz.efi` + `dtb/broadcom/bcm2712-rpi-5-b.dtb` via TFTP) -> kernel.

1. **U-Boot needs the downstream (Raspberry Pi) DT**, the kernel the
   mainline one. U-Boot dies on the mainline DT; the 6.18 kernel has no
   Ethernet with the downstream DT. The overlay (overlay patch 0003) now ships the
   downstream DTs of the pinned firmware release (1.20250430,
   byte-identical to v1.11.5.2's) at the boot partition root, next to
   `overlays/`, and the kernel's mainline DTs under `dtb/broadcom/`, where
   U-Boot's EFI boot loads `${fdtfile}` from.
2. **Squashfs failure** (`failed to mount squashfs: openfs failed: failed to
   create root filesystem: FSCONFIG_CMD_CREATE failed: invalid argument`)
   was not the kernel config (16K pages are fine; the UKI boots in QEMU with
   16K pages, via U-Boot EFI, with 640 MB RAM). U-Boot's EFI net boot TFTPs
   the ~160 MB UKI to `kernel_addr_r=0x00080000` and then the DT to
   `fdt_addr_r=0x02600000`, i.e. into the UKI's initrd -> initramfs zstd
   checksum fails, extensions and rootfs damaged. Reproduced exactly in
   QEMU (U-Boot EFI net boot). Fix: overlay patch 0002 (U-Boot patch `0002-rpi-load-the-kernel-UKI-above-fdt_addr_r`) moves
   `kernel_addr_r` to 0x02800000 (`ramdisk_addr_r` 0x1a800000); verified
   in QEMU. Only affected network boot of the UKI (the NVMe path loads
   GRUB, which is small).
3. **Consoles**: overlay kernel args are now `console=ttyAMA10,115200
   console=tty0` (tty0 last = /dev/console = Talos logs on HDMI; ttyAMA10
   is the Pi 5 debug UART with the mainline DT).
4. **D0 boards**: U-Boot's fdtfile is `broadcom/bcm2712-rpi-5-b.dtb` for
   every Pi 5 Model B stepping; U-Boot patch `0003-rpi-pick-the-mainline-D0-device-tree...` (overlay patch 0002) switches to
   `broadcom/bcm2712-d-rpi-5-b.dtb` when the firmware DT has the D0 pin
   controller (`brcm,bcm2712d0-pinctrl`).
5. U-Boot keeps the HDMI compatible backport and BOOTDELAY=5; the earlier
   debug options that changed boot behaviour (BOOTSTD_FULL, bootcmd
   `bootflow scan -lb`, LOG) are dropped.

### PXE (TFTP root) layout, from the installer image

| installer image path | TFTP path |
|---|---|
| `overlay/artifacts/arm64/u-boot/rpi5/u-boot.bin` | `u-boot.bin` |
| `overlay/artifacts/arm64/firmware/boot/bcm2712*.dtb` (downstream) | `bcm2712*.dtb` |
| `overlay/artifacts/arm64/firmware/boot/overlays/` | `overlays/` |
| `overlay/artifacts/arm64/firmware/boot/dtb/broadcom/bcm2712*.dtb` (mainline) | `dtb/broadcom/bcm2712*.dtb` |
| `usr/install/arm64/vmlinuz.efi` | `vmlinuz.efi` (+ `EFI/Linux/Talos.efi`) |
| `usr/install/arm64/systemd-boot.efi` | `systemd-boot.efi` (+ `EFI/boot/BOOTAA64.efi`) |

## Ethernet (macb)

The Pi 5 Ethernet stall fixes (sbc-raspberrypi#91) come in with the pkgs bump;
they are in `kernel/build/patches` at f694e1b:

- 0001-0003 `net: macb: ...` silent TX stall fixes (pkgs#1526, v2 #1546)
- 0008-0011 macb EEE/LPI support + enable EEE for RP1 (backport from Linux 7.1, pkgs#1629)
- 0004 PCI bridge-window shrink fix (pkgs#1536)

The config keeps `MACB=y`, `MISC_RP1=y`, `PINCTRL_RP1=y`, `COMMON_CLK_RP1=y`,
`PCIE_BRCMSTB=y`, `BCM2712_MIP=y`, NVMe built in.

## Patches

### `patches/siderolabs/pkgs/0001` - kernel config (config-arm64)

Same intent as v1.12.2, rebased onto pkgs f694e1b (6.18.51, now built with
clang). 3-way merge conflicts resolved by keeping the patch's intent:

- 16K pages, ondemand governor, IMA, ZSWAP off (also drops zsmalloc as before),
  DRM_PANTHOR off, BLK_CGROUP_IOLATENCY off, the ~100 module-to-builtin
  drivers, InfiniBand USER_MAD/USER_ACCESS off (USER_MEM/ODP dropped with it).
- Symbols upstream *newly* set to `=m` in 1.14 that the patch never touched
  stay `=m` (e.g. XEN_NETDEV_FRONTEND, HID_REDRAGON, INFINIBAND, IDPF,
  HID_MULTITOUCH, LIBETH_XDP, DWMAC_SUN55I, PCS_RZN1_MIIC).
- Upstream 1.14 moved ~75 options from `=y` to `=m`. Two of them are parents
  of drivers the patch builds in, so without a change kconfig would silently
  demote those to modules:
  - `MMC_SDHCI=y` (keeps the SDHCI drivers incl. `SDHCI_BRCMSTB` built in)
  - `USB_HID=y` (keeps the HID drivers built in)
  Verified with `make olddefconfig` on 6.18.51.

### `patches/siderolabs/talos/0001` - modules-arm64.txt

Upstream v1.14.1 list, minus the modules our config builds in, plus the
modules the v1.12.2 list added that still exist. Checked against the kernel
CI actually built (`ghcr.io/rubberbull-ai/kernel:v1.14.0-26-g138c6a4`, 307
modules): every listed file exists and Talos' depmod check
(`depmod --errsyms -w`) is clean. Dropped vs. the first attempt:
`usbhid.ko`, `sdhci.ko` (now built in), `cdc-phonet.ko` (PHONET off in 1.14);
re-added upstream modules that are still `=m` here (`idpf`, `libeth_xdp`,
`irdma`, `ublk_drv`, `hid-logitech`, `hid-lg-g15`). The module-list part that
v1.12.2 had put into patch 0003 is folded in here.

### `patches/siderolabs/talos/0002` - Skip NVRAM writes on arm64

Unchanged logic (`|| opts.Arch == arm64` on `--no-nvram`), new line offsets.

### `patches/siderolabs/talos/0003` - Force GRUB on arm64

Unchanged logic (`NewAuto()` returns GRUB on arm64); modules-list hunk moved to 0001.

## CI

- `workflow_dispatch` added: branch builds without a tag
  (`gh workflow run build.yaml --ref talos_v_1-14-1`). `make release` and the
  GitHub Release only run on `v*` tags.
- Runs on Ubicloud `ubicloud-standard-60-arm` (repo moved to the RubberBull-ai org).
- Images go to `ghcr.io/<lowercased repo owner>/...` = `ghcr.io/rubberbull-ai/...`
  (installer release tag: `ghcr.io/rubberbull-ai/installer:v1.14.1-rpi5`).
- No buildx registry layer cache: a `mode=max` registry cache made the kernel
  step slower (67 min vs 49 min uncached, the kernel build tree is huge) and
  was dropped; `mode=min` would not hit through the multi-stage `COPY --from`
  chains. Unchanged images are skipped instead (below).
- ghcr packages are private in the org. The imager runs in its own container
  without the runner's docker login, so the installer and disk-image steps
  pass `GITHUB_TOKEN` (Talos' imager authenticates ghcr.io with it via the
  go-containerregistry GitHub keychain).
- Skip-if-exists: `make image-tags` prints the content-derived image refs;
  CI skips Kernel / Overlay when `crane manifest` finds that exact tag, and
  skips the installer image builds when the marker tag
  `installer:<TALOS_TAG>-in-<hash of kernel/overlay tags, extensions, profile,
  Makefile>` exists (TALOS_TAG alone does not cover the installer's inputs).
  The disk image (`make disk-image`) is always written, so tag releases still
  get `metal-arm64.raw.zst`.
- `git am --committer-date-is-author-date` makes the patched checkout commits
  (and thus `PKGS_TAG`/`TALOS_TAG`, i.e. the kernel/installer image tags)
  identical across runs.

## Open TODOs

1. Boot-test on one Pi 5 (rpi-06) from PXE and NVMe with the fixes above
   (the risks listed above are addressed by them).
2. Verify Ethernet stability over a few days (macb fixes are in).
3. Consider moving the overlay to one that ships DTBs matched to the mainline
   kernel *and* a PCIe-capable U-Boot (e.g. once sbc-raspberrypi PR #88 lands).

---

# talos-builder v1.12.2 Upgrade (previous, never deployed)

Branch: `talos_v_1-12-2`

| Component | Before | After |
|-----------|--------|-------|
| Talos | v1.11.5 | v1.12.2 |
| Pkgs | v1.11.0 | v1.12.0 |
| SBC Overlay | `main` (fork) | v0.1.8 (upstream) |
| Upstream kernel | 6.12.38 | 6.17.7 |

Switched from the RPi Linux fork (stuck on 6.12.x) to the upstream Talos
kernel with config-only changes, and to the upstream siderolabs overlay
(reverted again in v1.14.1, see above). CI for tag `v1.12.2-pre` failed three
times after pushing the installer.
