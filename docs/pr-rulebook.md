# talos-builder PR Rulebook

Extends the federal rulebook, `docs/rulebook.md` on `main` of `RubberBull-ai/openclaw`.
Only what is true of this repo alone. A rule already in the federal file is not
restated here (F2). Jef, the OpenClaw agent (`jeff-rubberbull-ai`), reviews against
both; `/jef <n>` from the admin plugin asks him.

- **talos-builder-1 (MUST) PRs target this repo.** This is a fork; a bare `gh pr create`
  opens the PR on the upstream siderolabs repository. Every PR is opened with
  `-R RubberBull-ai/talos-builder` and the body of the first comment confirms the base
  repository. A PR that landed upstream is closed there at once.
- **talos-builder-2 (MUST) Tags are `v<talos>-rpi5.<n>`.** A build of the same Talos
  version bumps `<n>`; a new Talos version resets it to 1. The PR body names the Talos
  version, the kernel version and every patch carried, with its origin (mainline commit,
  RPi fork commit, ours).
- **talos-builder-3 (MUST) No machine config in a PR, an issue or a log.**
  `talosctl get mc` unfiltered prints the cluster CA keys. Quote one field with a
  `--output jsonpath` selector; never paste the object.
- **talos-builder-4 (MUST) A kernel or driver change names the symptom it addresses.**
  For the Pi 5 NIC: RP1 macb TX stalls and the etcd elections they cause. Proof of
  effect is federal B1.
- **talos-builder-5 (MUST) The upgrade path is stated.** A new image tag says which
  installed versions may upgrade to it in place and which need the Longhorn gate first;
  talos `docs` and the `talos-upgrade` skill are updated in a referenced PR when the
  path changes.
- **talos-builder-6 (MUST) Boot-tested before the tag.** A kernel or image change is
  booted on at least one Pi 5, NVMe and PXE, before its tag is pushed; the PR body names
  the node and what was checked (U-Boot device tree, squashfs mount, board DT).
  Why: the rpi-06 test of 2026-09-19 caught three boot-chain bugs an untested tag would
  have shipped to the fleet.
- **talos-builder-7 (MUST) Every patch names its origin.** A file under `patches/` states
  where it comes from (mainline commit or PR, Raspberry Pi fork commit, or our own fix
  with its issue link) and why it is carried; a patch without provenance is rejected.
- **talos-builder-8 (SHOULD) Staged rollout order.** A PR that changes what boots on the
  fleet states the order: one test Pi, then control planes with the etcd leader last,
  then workers, with a Longhorn and etcd health gate between nodes. Rolling all control
  planes at once needs a written reason.
