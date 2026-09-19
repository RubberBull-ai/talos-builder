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
modules the v1.12.2 list added. Removals cross-checked against
`make olddefconfig` of this config on 6.18.51; the depmod step of the Talos
build (fails on any missing/unresolved module) is the final check. The module-list part that
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

## Open TODOs

1. Boot-test on one Pi 5 (rpi-06) from NVMe before rollout (see risks above).
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
