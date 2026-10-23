#!/bin/bash
# Installs a built bundle, starts Studio under Xvfb and screenshots its largest window.
# Fails if no Studio window appears, so it doubles as an end-to-end test of the package.
#
# Usage: ci/smoke-test.sh BUNDLE.flatpak OUTPUT_DIR
# Needs: flatpak, Xvfb, xdotool, ImageMagick (import).
set -euo pipefail

bundle=$1
out=$2
app=io.github.mdarocha.BrickLinkStudio
display=:99
# Wine prefix creation, corefonts, the installer and Studio's first start add up to several minutes.
timeout_s=1800
settle_s=120

mkdir -p "$out"

flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user --noninteractive --assumeyes --bundle "$bundle"

Xvfb "$display" -screen 0 1920x1080x24 &
xvfb_pid=$!
trap 'kill "$xvfb_pid" 2>/dev/null || true' EXIT
export DISPLAY=$display
sleep 3

flatpak run --env=STUDIO_UNATTENDED_INSTALL=1 "$app" >"$out/studio.log" 2>&1 &
studio_pid=$!

largest_window() {
    local id best="" best_area=0 w h
    for id in $(xdotool search --onlyvisible --class 'studio\.exe' 2>/dev/null); do
        eval "$(xdotool getwindowgeometry --shell "$id")"
        w=$WIDTH h=$HEIGHT
        if (( w * h > best_area )); then
            best=$id best_area=$((w * h))
        fi
    done
    [[ -n "$best" ]] && printf '%s\n' "$best"
}

start=$SECONDS
until largest_window >/dev/null; do
    if ! kill -0 "$studio_pid" 2>/dev/null; then
        echo "launcher exited before a Studio window appeared" >&2
        import -window root "$out/failure.png" || true
        exit 1
    fi
    if (( SECONDS - start > timeout_s )); then
        echo "no Studio window after ${timeout_s}s" >&2
        import -window root "$out/failure.png" || true
        exit 1
    fi
    sleep 10
done

echo "Studio window appeared after $((SECONDS - start))s; waiting ${settle_s}s for it to finish loading"
sleep "$settle_s"
import -window "$(largest_window)" "$out/main.png"
echo "saved $out/main.png"
