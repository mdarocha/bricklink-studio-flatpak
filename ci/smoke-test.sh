# shellcheck shell=bash
# Installs the app from a built OSTree repo, runs it in headless GNOME Shell and screenshots
# its welcome screen; fails if Studio never gets there.
# Usage: nix run .#smoke-test -- REPO_DIR OUTPUT_DIR (uses a throwaway HOME)

app=io.github.mdarocha.bricklink-studio-flatpak
wm_class=studio.exe
shell_object=/io/github/mdarocha/BrickLinkStudio/SmokeTest
shell_interface=io.github.mdarocha.BrickLinkStudio.SmokeTest

# Flathub asks for windows of at most 1000x700, title bar included.
window_size=(1000 700)
# Offsets from the centre of Studio's client area, measured at window_size.
decline_tracking=(-24 188)
dismiss_tutorial=(377 -44)
# Empty sidebar space; anywhere else leaves a hover highlight in the screenshot.
idle_pointer=(-370 230)

# First start took 3 minutes locally; with the Wine installer it took 20 to 35 on GitHub runners.
window_timeout_s=2700
startup_timeout_s=300

if [[ -z "${SMOKE_TEST_SESSION:-}" ]]; then
    repo=$(realpath "$1")
    out=$(realpath -m "$2")
    work=$(mktemp -d)
    trap 'chmod -R u+w "$work"; rm -rf "$work"' EXIT

    mkdir -p "$out" "$work/home" "$work/runtime"
    chmod 700 "$work/runtime"
    # dbus-run-session gives GNOME Shell and the app their own session bus.
    env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_CACHE_HOME -u XDG_STATE_HOME \
        -u WAYLAND_DISPLAY -u DISPLAY -u XAUTHORITY \
        HOME="$work/home" XDG_RUNTIME_DIR="$work/runtime" SMOKE_TEST_SESSION=1 \
        dbus-run-session --config-file="$SMOKE_TEST_DBUS_CONFIG" -- "$0" "$repo" "$out"
    exit
fi

repo=$1
out=$2

shell_call() {
    local method=$1
    shift
    gdbus call --session --dest org.gnome.Shell --object-path "$shell_object" \
        --method "$shell_interface.$method" "$@"
}

window_titles() {
    shell_call WindowTitles 2>/dev/null || true
}

cleanup() {
    flatpak kill "$app" 2>/dev/null || true
    [[ -n "${shell_pid:-}" ]] && kill "$shell_pid" 2>/dev/null || true
}
trap cleanup EXIT

fail() {
    echo "$1" >&2
    echo "windows: $(window_titles)" >&2
    shell_call CaptureScreen "'$out/failure.png'" >/dev/null 2>&1 || true
    exit 1
}

wait_for_log() {
    local pattern=$1 timeout_s=$2 start=$SECONDS
    until grep -qE "$pattern" "$out/studio.log"; do
        kill -0 "$studio_pid" 2>/dev/null || fail "Studio exited while waiting for: $pattern"
        (( SECONDS - start < timeout_s )) || fail "no '$pattern' in Studio's log after ${timeout_s}s"
        sleep 2
    done
}

click() {
    shell_call Click "'$wm_class'" "int32 $1" "int32 $2" >/dev/null
}

flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
# Bundles can't install extra-data apps (flatpak/flatpak#1334).
flatpak remote-add --user --if-not-exists --no-gpg-verify ci-build "file://$repo"
flatpak install --user --noninteractive --assumeyes ci-build "$app"

# Only the smoke-test mode and extension; anything from the host would change GNOME's defaults.
XDG_DATA_DIRS=$SMOKE_TEST_SHELL_DATA GSETTINGS_BACKEND=memory \
    gnome-shell --headless --wayland --wayland-display=smoke-test \
    --virtual-monitor 1920x1080 --mode=smoke-test >"$out/gnome-shell.log" 2>&1 &
shell_pid=$!

start=$SECONDS
until shell_call X11Display >/dev/null 2>&1; do
    kill -0 "$shell_pid" 2>/dev/null || fail "GNOME Shell exited; see gnome-shell.log"
    (( SECONDS - start < 60 )) || fail "GNOME Shell's smoke-test extension did not come up"
    sleep 1
done
read -r display xauthority < <(shell_call X11Display | sed -E "s/^\('([^']*)', '([^']*)'\)$/\1 \2/")

DISPLAY=$display XAUTHORITY=$xauthority \
    flatpak run --env=STUDIO_UNATTENDED_INSTALL=1 "$app" >"$out/studio.log" 2>&1 &
studio_pid=$!

start=$SECONDS
until [[ "$(shell_call HasWindow "'$wm_class'")" == "(true,)" ]]; do
    kill -0 "$studio_pid" 2>/dev/null || fail "launcher exited before a Studio window appeared"
    elapsed=$((SECONDS - start))
    (( elapsed < window_timeout_s )) || fail "no Studio window after ${window_timeout_s}s"
    if (( elapsed % 60 < 5 )); then
        echo "waiting for a Studio window (${elapsed}s); windows: $(window_titles)"
    fi
    sleep 5
done
echo "Studio window appeared after $((SECONDS - start))s"

wait_for_log 'Executing step: .*CheckUnityAnalyticsConsentStep' "$startup_timeout_s"
# Unity applies its saved resolution during startup, so resize only once it is running.
shell_call PlaceWindow "'$wm_class'" "int32 ${window_size[0]}" "int32 ${window_size[1]}" >/dev/null
# Also lets the consent dialog fade in.
sleep 10
click "${decline_tracking[@]}"
wait_for_log 'Completed step: .*CheckUnityAnalyticsConsentStep' 60
# The first initialization sequence only loads the Build Mode scene, whose sequence opens the welcome screen.
wait_for_log 'Completed step: .*ShowWelcomeScreenOrOpenEmptyFileStep' "$startup_timeout_s"

# Featured models and banners load from BrickLink after the welcome screen opens.
sleep 15
if grep -q 'WindowsVideoMedia error' "$out/studio.log"; then
    fail "the tutorial banner's video failed to play; see patches/wine-unity-video.patch"
fi
frame_size=$(shell_call FrameSize "'$wm_class'")
[[ "$frame_size" == "(${window_size[0]}, ${window_size[1]})" ]] ||
    fail "Studio window is $frame_size, not ${window_size[*]}; click offsets would miss"
click "${dismiss_tutorial[@]}"
shell_call Hover "'$wm_class'" "int32 ${idle_pointer[0]}" "int32 ${idle_pointer[1]}" >/dev/null
sleep 5

shell_call CaptureWindow "'$wm_class'" "'$out/main.png'" >/dev/null
echo "saved $out/main.png after $((SECONDS - start))s"
