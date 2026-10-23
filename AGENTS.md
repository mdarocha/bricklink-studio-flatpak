# Agent notes

Maintainer docs are in `docs/maintainers-notes.md`. This file covers findings not written down there.

## Environment

- The maintainer's machine runs NixOS: there is no `/bin/bash`, so scripts use `#!/usr/bin/env bash`.
- Experiment with Flatpak in a throwaway `HOME` (`env HOME=/tmp/x flatpak --user ...`) so the
  maintainer's own installation and `~/.var/app` stay untouched. `ci/smoke-test.sh` does the same.
- `pkill -f PATTERN` also matches the shell running it if the pattern is in its command line.

## Checks after changes

- `nix build .#smoke-test` runs shellcheck on `ci/smoke-test.sh`.
- `nix run nixpkgs#actionlint -- .github/workflows/*.yml`.
- After touching any `uses:`, regenerate the lockfile with `gh actions-lock` (see the maintainer notes).
- A full smoke test needs network and 10+ minutes locally; CI takes about 40.

## Studio under Wine

- Studio is a Unity 2022.3 app. It logs to stdout, captured as `smoke-test/studio.log`.
  Startup is a sequence of `Executing step: ...` / `Completed step: ...` lines ending in
  `Initialization sequence completed.`; these are the reliable progress markers.
- The Unity Analytics consent dialog (`CheckUnityAnalyticsConsentStep`) appears on every start of a
  signed-out install. The answer is not stored in the registry PlayerPrefs or in AppData, so it
  can't be preseeded; the smoke test clicks "Decline tracking".
- Unity ignores pointer clicks unless the pointer moved there first, and ignores Escape on dialogs.
- Under bare Xvfb (no window manager), Unity ignores external window resizes and renders clipped.
  Under Mutter the layout reflows properly.
- The tutorial banner's video doesn't play under Wine (`WindowsVideoMedia error 0x80004001`), which
  leaves an empty box; the smoke test dismisses the banner.
- First start (Wine prefix, core fonts, single-threaded Inno Setup extraction) takes about 15
  minutes on a desktop and 20 to 35 on a GitHub runner.

## Headless GNOME Shell

- Xwayland started by Mutter needs the `XAUTHORITY` from Mutter's environment; the smoke-test
  extension returns it with `DISPLAY`.
- GNOME's window screenshot is `windowActor.paint_to_content(null)`. For X11 windows the
  frames client draws the shadow inside the actor's buffer, so this includes it.
- `XDG_DATA_DIRS` must not include host directories: NixOS ships gsettings overrides (e.g. extra
  title bar buttons) that would make screenshots differ from GNOME defaults.
- The extension's `shell-version` comes from nixpkgs' gnome-shell in `flake.nix`, so a flake.lock
  bump to a new GNOME major needs no manual change, but may need API fixes in `extension.js`.
- `dbus-run-session` with nixpkgs' default config also loads `/etc/dbus-1` and fails on Ubuntu
  runners, where that file doesn't exist; `flake.nix` passes its own minimal config.

## GitHub runners

- nix-magic-setup's Nix volume sits on the same disk as `/`, leaving `/` with a few hundred MB.
  Anything large (the Flatpak installation, the Wine prefix, a cache-nix-action archive) has to
  live under `/nix`; the smoke-test job sets `TMPDIR=/nix/tmp` and uses the hestia cache.
