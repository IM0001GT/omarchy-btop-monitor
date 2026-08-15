# omarchy-btop-monitor

Restores the **btop** icon on the Omarchy Quattro bar and turns the hover into a live system panel: per-core CPU, RAM, GPU, and storage.

Omarchy Quattro dropped the stock btop widget from the default bar. This third-party plugin puts it back on the right side, next to Power.

| Action | What happens |
| --- | --- |
| Hover the CPU icon | Popup with CPU (overall + per core), RAM, GPU, and each disk |
| Click the icon | Launch or focus `btop` |

GPU sampling works on Intel (`intel_gpu_top`), NVIDIA (`nvidia-smi`), and AMD (`gpu_busy_percent`, then DRM fdinfo). Hybrid laptops use the first tool that actually returns a reading.

## BC-250 note

The [ASRock BC-250](https://www.asrock.com/) is a one-off piece of hardware: a cut-down PS5 Oberon / Cyan Skillfish APU sold as a mining board, with a nonstandard RDNA 2-ish GPU (`1002:13fe`) that Linux treats as an integrated `amdgpu` device. It is not a regular desktop Radeon. SMU telemetry on this chip is incomplete, so a lot of the usual AMD monitoring stack only half-works.

What we hit on Omarchy:

- `/sys/class/drm/card*/device/gpu_busy_percent` **exists** but `read()` returns `ENOTSUPP`
- `gpu_metrics` v2.2 is readable, but `average_gfx_activity` stays at `0xFFFF` (the well-known MangoHud “655%” bug)
- `radeontop` reports an unknown card and a stuck `0%`
- leftover `nvidia-smi` (from `nvidia-utils` on Omarchy) fails because there is no NVIDIA driver

This plugin still prefers the normal AMD sysfs busy node so ordinary Radeons keep working. On the BC-250 that node is a dead end, so we fall back to `/proc/*/fdinfo` `drm-engine-*` time — the same busy signal `nvtop` / `btop` use when the SMU field is junk. Load tracking is in good shape; clocks, power, and VRAM from hwmon were already fine. Full “desktop Radeon” support is not a realistic goal for this chip, but we are filling in the gaps that actually show up on the bar.

## Install

Omarchy plugins run as unsandboxed code inside `omarchy-shell`. Only add repos you trust.

```bash
omarchy plugin add https://github.com/IM0001GT/omarchy-btop-monitor --enable
```

That clones the plugin into `~/.config/omarchy/plugins/btop-monitor/`, validates the manifest, and can drop it on the bar.

For Intel or NVIDIA GPU numbers in the hover panel, also install the vendor tools:

```bash
~/.config/omarchy/plugins/btop-monitor/install.sh --deps
```

`--deps` is optional. Without it the widget still works; GPU just shows `n/a` until a sampler is available.

### One-shot from a clone

If you already cloned the repo (or downloaded a zip):

```bash
git clone https://github.com/IM0001GT/omarchy-btop-monitor.git
cd omarchy-btop-monitor
./install.sh
```

That installs GPU tools, adds the plugin, and places it rightmost in the right section (after `omarchy.power`).

## Update

If you installed with `omarchy plugin add`:

```bash
omarchy plugin update btop-monitor
```

## Uninstall

```bash
omarchy plugin remove btop-monitor
```

GPU packages and the optional sysctl drop-in are left in place. To drop the Intel sampling sysctl too:

```bash
sudo rm -f /etc/sysctl.d/99-omarchy-btop-monitor.conf
sudo sysctl --system
```

## Requirements

- [Omarchy](https://omarchy.org/) with the shell plugin CLI (`omarchy plugin add`)
- `btop` (already on Omarchy)
- `jq` (already on Omarchy)
- Optional GPU tools, installed by `./install.sh --deps`:

| GPU | Extra package | Notes |
| --- | --- | --- |
| Intel | `intel-gpu-tools` (+ `python`) | Sets `kernel.perf_event_paranoid=0` so `intel_gpu_top` can read the i915 PMU |
| NVIDIA | `nvidia-utils` | Only if `nvidia-smi` is missing |
| AMD | none | Prefers `/sys/class/drm/card*/device/gpu_busy_percent`. If that node is missing or `ENOTSUPP` (BC-250), falls back to DRM fdinfo engine time. |

Setting `kernel.perf_event_paranoid=0` lets unprivileged processes read CPU performance counters. That is required for `intel_gpu_top` as a regular user. Skip `--deps` if you do not want that change.

## Layout

```text
manifest.json          Omarchy plugin manifest (must live at repo root)
Btop.qml               Bar icon + hover panel
scripts/system-usage   CPU / RAM / GPU / disk sampler
install.sh             GPU deps + enable / place the widget
```

The repo root **is** the plugin. That is what `omarchy plugin add` and `omarchy plugin validate` expect.

## License

MIT. See [LICENSE](LICENSE).
