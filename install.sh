#!/bin/bash

# Install the btop-monitor Omarchy shell plugin.
#
# Preferred (git-managed, easy updates):
#   omarchy plugin add https://github.com/IM0001GT/omarchy-btop-monitor --enable
#   ./install.sh --deps
#
# This script:
#   1. Detects GPU vendor(s) via lspci (Intel / NVIDIA / AMD; hybrid OK).
#   2. Installs the GPU monitoring tool each vendor needs (sudo):
#        Intel  -> intel-gpu-tools, and sets kernel.perf_event_paranoid=0
#                 (persisted in /etc/sysctl.d/99-omarchy-btop-monitor.conf)
#        NVIDIA -> nvidia-utils (only if nvidia-smi is missing)
#        AMD    -> nothing (utilization comes from kernel sysfs)
#   3. Unless --deps is set, installs the plugin and enables it as a bar
#      widget, rightmost in the right section.
#
# Run it as your normal user; it calls sudo for the privileged steps.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="btop-monitor"
DEPS_ONLY=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [--deps] [-h|--help]

Install the btop-monitor Omarchy bar widget and optional GPU tools.

  --deps        Install GPU monitoring packages / sysctl only
  -h, --help    Show this help

Preferred install (git-managed, updates via omarchy plugin update):

  omarchy plugin add https://github.com/IM0001GT/omarchy-btop-monitor --enable
  ~/.config/omarchy/plugins/btop-monitor/install.sh --deps

Uninstall:

  omarchy plugin remove btop-monitor
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
[[ -f $SCRIPT_DIR/manifest.json && -f $SCRIPT_DIR/Btop.qml && -f $SCRIPT_DIR/scripts/system-usage ]] \
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

for vendor in "${vendors[@]}"; do
  case "$vendor" in
    intel)
      if ! command -v intel_gpu_top >/dev/null 2>&1; then
        echo "Installing intel-gpu-tools ..."
        privileged pacman -S --needed --noconfirm intel-gpu-tools
      else
        echo "intel-gpu-tools already installed."
      fi
      if ! command -v python3 >/dev/null 2>&1; then
        echo "Installing python (needed to parse intel_gpu_top JSON) ..."
        privileged pacman -S --needed --noconfirm python
      fi
      # intel_gpu_top reads the i915 PMU, which needs CPU event access.
      if [[ $(sysctl -n kernel.perf_event_paranoid 2>/dev/null || echo 2) -gt 0 ]]; then
        echo "Setting kernel.perf_event_paranoid=0 (persisted in /etc/sysctl.d/99-omarchy-btop-monitor.conf)"
        echo "This lets unprivileged processes read CPU performance counters so intel_gpu_top can sample the GPU."
        echo 'kernel.perf_event_paranoid=0' | privileged tee /etc/sysctl.d/99-omarchy-btop-monitor.conf >/dev/null
        privileged sysctl -w kernel.perf_event_paranoid=0 >/dev/null
      else
        echo "kernel.perf_event_paranoid already allows GPU sampling."
      fi
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
      echo "AMD: GPU utilization is read from kernel sysfs; no extra package needed."
      ;;
    *)
      echo "Unknown GPU vendor: the widget falls back to whatever GPU tool works at runtime."
      ;;
  esac
done

if (( DEPS_ONLY )); then
  echo
  echo "GPU dependencies done. Enable the widget with:"
  echo "  omarchy plugin add https://github.com/IM0001GT/omarchy-btop-monitor --enable"
  echo "  or: omarchy plugin enable $PLUGIN_ID --after omarchy.power"
  exit 0
fi

# --- install the plugin ---------------------------------------------------
plugin_dir="$real_home/.config/omarchy/plugins/$PLUGIN_ID"

copy_plugin_files() {
  echo "Installing plugin files to $plugin_dir ..."
  mkdir -p "$plugin_dir/scripts"
  install -m 0644 "$SCRIPT_DIR/manifest.json" "$plugin_dir/manifest.json"
  install -m 0644 "$SCRIPT_DIR/Btop.qml" "$plugin_dir/Btop.qml"
  install -m 0755 "$SCRIPT_DIR/scripts/system-usage" "$plugin_dir/scripts/system-usage"
  chown -R "$real_user:" "$plugin_dir" 2>/dev/null || true
}

if [[ $SCRIPT_DIR == "$plugin_dir" ]]; then
  echo "Already running from the installed plugin directory."
elif [[ -d $plugin_dir/.git ]]; then
  echo "Plugin already installed as a git checkout at $plugin_dir"
  echo "Update later with: omarchy plugin update $PLUGIN_ID"
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

echo
echo "Done. 'btop System Monitor' is now a bar widget at the far right."
echo "  Hover the CPU icon -> CPU per core, RAM, GPU, and storage."
echo "  Click the icon     -> launch/focus btop."
echo "  GPU tool in use:   $(command -v nvidia-smi >/dev/null && nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || command -v intel_gpu_top || echo 'sysfs (AMD) / none')"
echo "  Uninstall: omarchy plugin remove $PLUGIN_ID"
