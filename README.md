# omarchy-btop-monitor

Restores the **btop** icon on the Omarchy Quattro bar and turns the hover into a live system panel: per-core CPU, RAM, GPU, and storage.

Omarchy Quattro dropped the stock btop widget from the default bar. This third-party plugin puts it back on the right side, next to Power.

| Action | What happens |
| --- | --- |
| Hover the CPU icon | Popup with CPU name and per-core bars, memory type/speed, GPU name, and storage model |
| Click the icon | Launch or focus `btop` |

GPU sampling works on Intel (DRM fdinfo / RC6 sysfs), NVIDIA (`nvidia-smi`), and AMD (`gpu_busy_percent`, then DRM fdinfo). Hybrid laptops use the first tool that actually returns a reading. Intel does **not** change `kernel.perf_event_paranoid`. The Intel headline GPU % is Render/3D (`render` / `gfx` / `compute`) averaged over the 2s refresh. `nvidia-smi` is used only when the NVIDIA driver is actually loaded, so a leftover binary cannot stall the panel.

## BC-250 note

The ASRock BC-250 is a cut-down Oberon / Cyan Skillfish board with a nonstandard RDNA 2-ish GPU (`1002:13fe`). Linux binds it as `amdgpu`, but SMU telemetry is incomplete:

- `/sys/class/drm/card*/device/gpu_busy_percent` exists, but `read()` returns `ENOTSUPP`
- `gpu_metrics` `average_gfx_activity` stays at `0xFFFF`
- `radeontop` reports an unknown card and a stuck `0%`

Ordinary Radeons still use the sysfs busy node. On the BC-250 the plugin falls back to `/proc/*/fdinfo` `drm-engine-*` time.

## Install

Omarchy plugins run as unsandboxed code inside `omarchy-shell`. Only add repos you trust.

```bash
omarchy plugin add https://github.com/IM0001GT/omarchy-btop-monitor --enable
```

That clones the plugin into `~/.config/omarchy/plugins/btop-monitor/`, validates the manifest, and can drop it on the bar.

Intel and AMD need no extra packages. On NVIDIA, if `nvidia-smi` is missing:

```bash
~/.config/omarchy/plugins/btop-monitor/install.sh --deps
```

`--deps` is optional. Without it the widget still works; a missing NVIDIA tool just shows `n/a` for GPU. If you installed an older version that set `kernel.perf_event_paranoid=0`, run `--deps` once to remove that drop-in.

### One-shot from a clone

If you already cloned the repo (or downloaded a zip):

```bash
git clone https://github.com/IM0001GT/omarchy-btop-monitor.git
cd omarchy-btop-monitor
./install.sh
```

That adds the plugin, places it rightmost in the right section (after `omarchy.power`), and installs NVIDIA tools only if needed.

## Update

If you installed with `omarchy plugin add`:

```bash
omarchy plugin update btop-monitor
```

## Uninstall

```bash
omarchy plugin remove btop-monitor
```

Current releases do not leave a sysctl drop-in. If an older install set `kernel.perf_event_paranoid=0`, remove it with:

```bash
~/.config/omarchy/plugins/btop-monitor/install.sh --deps
```

or by hand:

```bash
sudo rm -f /etc/sysctl.d/99-omarchy-btop-monitor.conf /etc/sysctl.d/50-perf-event.conf
sudo sysctl -w kernel.perf_event_paranoid=2
```

## Requirements

- [Omarchy](https://omarchy.org/) with the shell plugin CLI (`omarchy plugin add`)
- `btop` (already on Omarchy)
- `jq` (already on Omarchy)
- Optional NVIDIA tools, installed by `./install.sh --deps` only when `nvidia-smi` is missing:

| GPU | Extra package | Notes |
| --- | --- | --- |
| Intel | none | DRM fdinfo engine busy, then RC6 residency. No `kernel.perf_event_paranoid` change |
| NVIDIA | `nvidia-utils` | Only if `nvidia-smi` is missing |
| AMD | none | Prefers `/sys/class/drm/card*/device/gpu_busy_percent`. If that node is missing or `ENOTSUPP` (BC-250), falls back to DRM fdinfo engine time. |

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
