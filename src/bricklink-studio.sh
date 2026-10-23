#!/bin/bash
# Starts BrickLink Studio from the app's private Wine prefix.
#
# The installer Flatpak downloaded from BrickLink (/app/extra) is run into the prefix on
# first start, and again whenever an app update ships a different installer. Wine's
# Documents, Pictures and Downloads folders are linked to the host's XDG folders on every
# start, so models end up in the real ~/Documents (or its localized equivalent).
#
# Usage: bricklink-studio [MODEL.io ...]
#
# Environment:
#   STUDIO_DPI                 Windows DPI applied on every start: 96 = 100 %, 144 = 150 %, 192 = 200 %
#   STUDIO_VIRTUAL_DESKTOP     e.g. 2560x1440; runs Studio inside a Wine virtual desktop window,
#                              which avoids the focus/alt-tab problems Studio has as a plain X11 window
#   STUDIO_UNATTENDED_INSTALL  1 = install silently, accepting BrickLink's license agreement
#                              without displaying it; meant for CI, not for people
set -euo pipefail

installer=/app/extra/Studio+2.0.exe
installer_hash_file=/app/extra/installer.sha256
studio_dir="$WINEPREFIX/drive_c/Program Files/Studio 2.0"
studio_exe="$studio_dir/Studio.exe"
installed_marker="$WINEPREFIX/.installed-installer.sha256"

log() { printf 'bricklink-studio: %s\n' "$*" >&2; }

init_prefix() {
    [[ -f "$WINEPREFIX/system.reg" ]] && return 0
    log "creating Wine prefix in $WINEPREFIX"
    wineboot --init
    wineserver -w

    # Without the MS core fonts Studio's UI renders with substitute fonts and clipped labels.
    winetricks -q corefonts || log "corefonts install failed; continuing without them"
}

wine_user_dir() {
    local dir="$WINEPREFIX/drive_c/users/${USER:-$(id -un)}"
    if [[ ! -d "$dir" ]]; then
        for dir in "$WINEPREFIX"/drive_c/users/*; do
            [[ "${dir##*/}" != Public ]] && break
        done
    fi
    printf '%s\n' "$dir"
}

# Prints the host path of an XDG user folder. The sandbox's own XDG_CONFIG_HOME is per-app,
# so the host's user-dirs.dirs is exposed read-only at its real location and read from there.
xdg_dir() {
    local key=$1 fallback=$2 file value
    for file in "$HOME/.config/user-dirs.dirs" "${XDG_CONFIG_HOME:-/nonexistent}/user-dirs.dirs"; do
        [[ -r "$file" ]] || continue
        value=$(sed -n "s/^${key}=\"\(.*\)\"$/\1/p" "$file" | tail -n 1)
        if [[ -n "$value" ]]; then
            printf '%s\n' "${value//\$HOME/$HOME}"
            return 0
        fi
    done
    printf '%s\n' "$HOME/$fallback"
}

link_user_folder() {
    local link="$1/$2" target=$3

    # A folder pointing at $HOME itself is a common way to "disable" an XDG dir; $HOME is not
    # shared with the sandbox, so linking it would only expose an empty directory.
    [[ -d "$target" && "$target" != "$HOME" ]] || return 0
    [[ -L "$link" && "$(readlink -- "$link")" == "$target" ]] && return 0

    if [[ -d "$link" && ! -L "$link" ]]; then
        if ! rmdir -- "$link" 2>/dev/null; then
            log "not linking $2 to $target: $link already contains files"
            return 0
        fi
    else
        rm -f -- "$link"
    fi
    ln -s -- "$target" "$link"
}

link_user_folders() {
    local user_dir
    user_dir=$(wine_user_dir)
    link_user_folder "$user_dir" Documents "$(xdg_dir XDG_DOCUMENTS_DIR Documents)"
    link_user_folder "$user_dir" Pictures "$(xdg_dir XDG_PICTURES_DIR Pictures)"
    link_user_folder "$user_dir" Downloads "$(xdg_dir XDG_DOWNLOAD_DIR Downloads)"
}

studio_running() {
    grep -qaF 'Studio 2.0\Studio.exe' /proc/[0-9]*/cmdline 2>/dev/null
}

install_if_needed() {
    local wanted current=""
    wanted=$(<"$installer_hash_file")
    [[ -f "$installed_marker" ]] && current=$(<"$installed_marker")
    [[ -f "$studio_exe" && "$wanted" == "$current" ]] && return 0

    local args=(/SP- /NORESTART)
    if [[ "${STUDIO_UNATTENDED_INSTALL:-0}" == 1 ]]; then
        args+=(/VERYSILENT /SUPPRESSMSGBOXES)
    elif [[ -f "$studio_exe" ]]; then
        # Upgrade: progress window only. The license agreement was shown on the first install.
        args+=(/SILENT)
    fi

    log "running the Studio installer"
    wine "$installer" "${args[@]}"

    if [[ ! -f "$studio_exe" ]]; then
        log "installer finished but $studio_exe is missing (cancelled, or installed elsewhere)"
        exit 1
    fi
    printf '%s\n' "$wanted" > "$installed_marker"

    # The interactive installer can start Studio on its last page; don't open a second copy.
    if studio_running; then
        wineserver -w
        exit 0
    fi
}

apply_dpi() {
    [[ -n "${STUDIO_DPI:-}" ]] || return 0
    wine reg add 'HKCU\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d "$STUDIO_DPI" /f >/dev/null
}

run_studio() {
    local args=() f
    for f in "$@"; do
        args+=("$(winepath -w "$f")")
    done

    # Same working directory a Windows shortcut would use; some apps resolve data files against it.
    cd "$studio_dir"
    if [[ -n "${STUDIO_VIRTUAL_DESKTOP:-}" ]]; then
        exec wine explorer "/desktop=BrickLinkStudio,$STUDIO_VIRTUAL_DESKTOP" "$studio_exe" "${args[@]}"
    fi
    exec wine "$studio_exe" "${args[@]}"
}

init_prefix
link_user_folders
install_if_needed
apply_dpi
run_studio "$@"
