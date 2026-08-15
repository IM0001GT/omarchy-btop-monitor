#!/bin/bash

# Optional helper for Hardware Tooltip.
#
# Preferred install (no root):
#   omarchy plugin add https://github.com/IM0001GT/omarchy-hw-tooltip --enable
#
# This script:
#   1. Detects GPU vendor(s) via lspci (Intel / NVIDIA / AMD; hybrid OK).
#   2. With --deps, installs nvidia-utils only if nvidia-smi is missing.
#      Intel and AMD need no extra packages and no sysctl changes.
#   3. Removes any leftover perf_event_paranoid drop-in from older builds.
#   4. Unless --deps is set, enables the widget and restarts omarchy-shell.
#
# Run it as your normal user; sudo is used only for the optional NVIDIA
# package and leftover sysctl cleanup.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="im0001gt.hw-tooltip"
LEGACY_IDS=(btop-monitor)
DEPS_ONLY=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [--deps] [-h|--help]

Enable or update Hardware Tooltip, or install optional NVIDIA tools.

  --deps        Install nvidia-utils only if nvidia-smi is missing;
                remove leftover sysctl drop-ins from older builds
  -h, --help    Show this help

Preferred install (no root):

  omarchy plugin add https://github.com/IM0001GT/omarchy-hw-tooltip --enable

A shell restart is required after an update so Quickshell loads the new QML.

Uninstall:

  omarchy plugin remove im0001gt.hw-tooltip
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --deps) DEPS_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# --- resolve the real target user (works when run via sudo) -------------
if [[ -n ${SUDO_USER:-} ]]; then
  real_user="$SUDO_USER"
elif [[ -n ${DOAS_USER:-} ]]; then
  real_user="$DOAS_USER"
else
  real_user="${USER:-$(id -un)}"
fi
real_home="$(getent passwd "$real_user" | cut -d: -f6 2>/dev/null || true)"
if [[ -z $real_home || ! -d $real_home ]]; then
  echo "error: cannot resolve home directory for user '$real_user'" >&2
  exit 1
fi

if [[ $(id -u) -eq 0 ]]; then
  run_as_user() { runuser -u "$real_user" -- "$@"; }
  privileged() { "$@"; }
else
  run_as_user() { "$@"; }
  privileged() { sudo "$@"; }
fi

# --- sanity checks -------------------------------------------------------
for cmd in lspci pacman jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "error: missing required command: $cmd" >&2; exit 1; }
done
[[ -f $SCRIPT_DIR/manifest.json && -f $SCRIPT_DIR/HardwareTooltip.qml && -f $SCRIPT_DIR/scripts/system-usage ]] \
  || { echo "error: plugin sources not found next to this script" >&2; exit 1; }

# --- GPU detection -------------------------------------------------------
# Collect every vendor so hybrid laptops get tools for both GPUs.
gpu_vendors() {
  local pair id
  declare -A seen=()
  for pair in $(lspci -nn 2>/dev/null \
      | grep -iE 'vga compatible|3d controller|display controller' \
      | grep -oE '\[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]' | tr -d '[]' || true); do
    id=${pair%%:*}
    case "$id" in
      8086) seen[intel]=1 ;;
      10de) seen[nvidia]=1 ;;
      1002) seen[amd]=1 ;;
    esac
  done
  if (( ${#seen[@]} == 0 )); then
    echo "unknown"
    return
  fi
  printf '%s\n' "${!seen[@]}"
}

mapfile -t vendors < <(gpu_vendors)
echo "Detected GPU vendor(s): ${vendors[*]}"

remove_legacy_perf_sysctl() {
  local f changed=0
  for f in /etc/sysctl.d/99-omarchy-btop-monitor.conf /etc/sysctl.d/50-perf-event.conf; do
    [[ -f $f ]] || continue
    if awk '
      BEGIN { ours = 0 }
      /^[[:space:]]*$/ { next }
      /^[[:space:]]*#/ { next }
      $0 == "kernel.perf_event_paranoid=0" { ours = 1; next }
      { exit 2 }
      END { exit ours ? 0 : 1 }
    ' "$f"; then
      echo "Removing leftover perf_event_paranoid drop-in $f"
      privileged rm -f "$f"
      changed=1
    fi
  done
  if (( changed )); then
    echo "Restoring kernel.perf_event_paranoid to the system default (2)."
    privileged sysctl -w kernel.perf_event_paranoid=2 >/dev/null
  fi
}

remove_legacy_perf_sysctl

for vendor in "${vendors[@]}"; do
  case "$vendor" in
    intel)
      echo "Intel: GPU utilization is read from DRM fdinfo / RC6 sysfs; no extra package or sysctl needed."
      ;;
    nvidia)
      if ! command -v nvidia-smi >/dev/null 2>&1; then
        echo "Installing nvidia-utils ..."
        privileged pacman -S --needed --noconfirm nvidia-utils
      else
        echo "nvidia-smi already available."
      fi
      ;;
    amd)
      echo "AMD: utilization from sysfs, or DRM fdinfo if busy percent is unsupported (BC-250); no extra package needed."
      ;;
    *)
      echo "Unknown GPU vendor: the widget falls back to whatever GPU tool works at runtime."
      ;;
  esac
done

if (( DEPS_ONLY )); then
  echo
  echo "Dependency step done (Intel/AMD need nothing; NVIDIA only if nvidia-smi was missing)."
  exit 0
fi

# --- install the plugin ---------------------------------------------------
plugin_dir="$real_home/.config/omarchy/plugins/$PLUGIN_ID"

copy_plugin_files() {
  echo "Installing plugin files to $plugin_dir ..."
  mkdir -p "$plugin_dir/scripts"
  install -m 0644 "$SCRIPT_DIR/manifest.json" "$plugin_dir/manifest.json"
  install -m 0644 "$SCRIPT_DIR/HardwareTooltip.qml" "$plugin_dir/HardwareTooltip.qml"
  install -m 0755 "$SCRIPT_DIR/scripts/system-usage" "$plugin_dir/scripts/system-usage"
  chown -R "$real_user:" "$plugin_dir" 2>/dev/null || true
}

reload_shell() {
  echo "Restarting omarchy-shell so the new plugin code is loaded ..."
  rm -rf "$real_home/.cache/quickshell/qmlcache" 2>/dev/null || true
  if ! run_as_user omarchy restart shell; then
    echo "warning: could not restart the shell. Run: omarchy restart shell" >&2
  fi
}

if [[ $SCRIPT_DIR == "$plugin_dir" ]]; then
  echo "Already running from the installed plugin directory."
elif [[ -d $plugin_dir/.git ]]; then
  echo "Plugin already installed as a git checkout. Updating ..."
  run_as_user omarchy plugin update "$PLUGIN_ID" --yes || \
    echo "warning: omarchy plugin update failed; restarting with the files already on disk." >&2
elif [[ ! -e $plugin_dir ]]; then
  origin=""
  if git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    origin=$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || true)
  fi
  if [[ -n $origin ]] && run_as_user omarchy plugin add "$origin" --yes; then
    echo "Added $PLUGIN_ID from $origin"
  else
    [[ -z $origin ]] || echo "omarchy plugin add failed; copying files instead."
    copy_plugin_files
  fi
else
  copy_plugin_files
fi

for legacy in "${LEGACY_IDS[@]}"; do
  legacy_dir="$real_home/.config/omarchy/plugins/$legacy"
  if [[ -e $legacy_dir && $legacy_dir != "$plugin_dir" && $legacy_dir != "$SCRIPT_DIR" ]]; then
    echo "Note: older checkout still at $legacy_dir"
    echo "      Remove it with: omarchy plugin remove $legacy"
  fi
done

# --- discover and enable ---------------------------------------------------
run_as_user omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

discovered=0
for (( attempt = 0; attempt < 60; attempt++ )); do
  if run_as_user omarchy-plugin-catalog 2>/dev/null | jq -e --arg id "$PLUGIN_ID" \
      'any(.[]; .id == $id)' >/dev/null 2>&1; then
    discovered=1
    break
  fi
  sleep 0.1
done
if (( ! discovered )); then
  echo "warning: plugin not discovered yet; retrying once ..." >&2
  run_as_user omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  for (( attempt = 0; attempt < 60; attempt++ )); do
    if run_as_user omarchy-plugin-catalog 2>/dev/null | jq -e --arg id "$PLUGIN_ID" \
        'any(.[]; .id == $id)' >/dev/null 2>&1; then
      discovered=1
      break
    fi
    sleep 0.1
  done
fi
if (( ! discovered )); then
  echo "error: plugin '$PLUGIN_ID' was not discovered by the shell" >&2
  exit 1
fi

echo "Plugin discovered. Placing it rightmost in the right section ..."
if ! run_as_user omarchy plugin enable "$PLUGIN_ID" --after omarchy.power; then
  echo "omarchy.power not found in the layout; appending to the right section instead."
  run_as_user omarchy plugin enable "$PLUGIN_ID" --section right
fi

reload_shell

echo
echo "Done. Hardware Tooltip is now a bar widget at the far right."
echo "  Hover the chip icon -> CPU per core, RAM, GPU, and storage."
echo "  Click the icon      -> launch/focus btop."
echo "  Uninstall: omarchy plugin remove $PLUGIN_ID"
