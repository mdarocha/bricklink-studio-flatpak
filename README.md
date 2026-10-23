> ⚠️ **100% vibecoded codebase**

# BrickLink Studio Flatpak

Unofficial Flatpak of [BrickLink Studio](https://www.bricklink.com/v3/studio/main.page), the brick
model designer. It runs the official Windows build with Wine, fully inside the Flatpak sandbox:
no Wine on the host, no shared `~/.wine` prefix, no stray `.desktop` files.

This repository contains only build instructions and scripts. BrickLink Studio itself is never
stored here or in the published Flatpak repo; Flatpak downloads the installer from BrickLink's
servers on your machine when you install the app.

Not affiliated with, endorsed or supported by BrickLink or the LEGO Group.

## How it works

- **Wine** comes from Flathub's `org.winehq.Wine` base app (branch `stable-25.08`, Wine 11.0,
  with winetricks). It is copied into this app at build time.
- **Studio** is an `extra-data` source: the manifest holds only the URL of the installer in
  BrickLink's versioned archive, its size and its sha256. Flatpak downloads and verifies it at
  install time and puts it in `/app/extra`.
- **First start** creates a private Wine prefix in
  `~/.var/app/io.github.mdarocha.BrickLinkStudio/data/prefix`, installs the MS core fonts and
  opens BrickLink's installer, including its license agreement. Click through with the default
  install location.
- **App updates** ship a new installer; on the next start the launcher notices it changed and runs
  it again silently over the existing install.
- **Your folders**: Wine's Documents, Pictures and Downloads are symlinked to your real XDG
  folders, read from `~/.config/user-dirs.dirs`, so localized names like `~/Dokumenty` work.
  Models land where you'd expect, and renders can go straight to Pictures. Those three folders
  are the only parts of your home directory the app can see.
- **`.io` files** get a MIME type and open in Studio from the file manager.

## Install from the Flatpak remote

The runtime comes from Flathub, so add it first if you don't have it:

```sh
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak remote-add --user --if-not-exists bricklink-studio \
    https://mdarocha.github.io/bricklink-studio-flatpak/bricklink-studio.flatpakrepo
flatpak install --user bricklink-studio io.github.mdarocha.BrickLinkStudio
```

After the remote is added the app also shows up in GNOME Software and KDE Discover, and updates
arrive with `flatpak update`. The landing page at
<https://mdarocha.github.io/bricklink-studio-flatpak/> has a one-click `.flatpakref` as well.

## Build locally

### Prerequisites

NixOS:

```nix
services.flatpak.enable = true;
xdg.portal.enable = true;          # GNOME and Plasma modules already enable this
environment.systemPackages = [ pkgs.flatpak-builder ];
```

Other distributions: install `flatpak` and `flatpak-builder` from your package manager.
`scripts/upstream.py` needs only Python 3 (standard library).

### Build, install, run

```sh
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

flatpak-builder --user --install --install-deps-from=flathub --force-clean \
    build-dir io.github.mdarocha.BrickLinkStudio.yml
flatpak run io.github.mdarocha.BrickLinkStudio
```

`--install-deps-from` pulls the Freedesktop 25.08 runtime and the Wine base app. The build itself
copies a handful of files and takes seconds. The installer is downloaded during
`--install`, not during the build.

To build a single-file bundle instead:

```sh
flatpak-builder --repo=repo --default-branch=stable --force-clean build-dir io.github.mdarocha.BrickLinkStudio.yml
flatpak build-bundle repo bricklink-studio.flatpak io.github.mdarocha.BrickLinkStudio stable
```

### Checking metadata

```sh
appstreamcli validate --no-net data/io.github.mdarocha.BrickLinkStudio.metainfo.xml
desktop-file-validate data/io.github.mdarocha.BrickLinkStudio.desktop
```

## Options

Set with `flatpak override --user --env=NAME=value io.github.mdarocha.BrickLinkStudio`:

| Variable | Effect |
|---|---|
| `STUDIO_DPI` | Windows DPI, applied on every start. `144` = 150 %, `192` = 200 %. Wine defaults to 96, which is tiny on 4K screens. |
| `STUDIO_VIRTUAL_DESKTOP` | e.g. `3840x2160`. Runs Studio inside a Wine virtual desktop window. Use it if dialogs lose focus or alt-tab freezes Studio. |
| `STUDIO_UNATTENDED_INSTALL` | `1` installs silently, accepting BrickLink's license agreement without showing it. Meant for CI. |

Wine tools work through `--command`:

```sh
flatpak run --command=winecfg io.github.mdarocha.BrickLinkStudio
flatpak run --command=winetricks io.github.mdarocha.BrickLinkStudio <verb>
```

## Updates

`.github/workflows/update.yml` runs every Monday. `scripts/upstream.py` reads BrickLink's version
list (`version_Patch_OpenBeta.txt`, the same source winget's updater uses), and if there is a newer
release it downloads the installer from
`https://studio.download.bricklink.info/Studio2.0/Archive/<version>/Studio+2.0.exe`, measures its
size and sha256, rewrites the manifest's extra-data entry and adds a `<release>` to the metainfo.
It then opens a PR and starts the Build workflow on that branch, which installs the result and
starts Studio. Merge when it is green; main publishes to the remote.

Run it by hand from the Actions tab ("Check for Studio updates"), optionally pinning a version,
or locally with `python3 scripts/upstream.py update [--version 2.26.9_1]`.

Studio's own in-app updater still works inside the prefix, but updates through the Flatpak are
the ones that stick across reinstalls.

## CI

| Workflow / job | Runs on | Does |
|---|---|---|
| Build / verify-upstream | every push, PR, dispatch | Downloads the installer the manifest points at and checks size and sha256. |
| Build / build | same | Builds in the Flathub `freedesktop-25.08` container. On main: signs commits, regenerates the summary and appstream data. |
| Build / smoke-test | same | Installs the bundle on a runner, starts it under Xvfb with an unattended install, waits for Studio's window and screenshots it. |
| Build / deploy | main only | Publishes the signed OSTree repo, `.flatpakrepo`, `.flatpakref`, icon, screenshot and a landing page to GitHub Pages. |
| Check for Studio updates | Mondays, dispatch | Opens an update PR as described above. |

The metainfo screenshot URL points at the screenshot the smoke test publishes, so the store listing
shows the real app without any BrickLink images being stored in this repository. If a smoke test
fails, the deploy keeps the previously published screenshot.

## Layout

```
io.github.mdarocha.BrickLinkStudio.yml   Flatpak manifest
src/bricklink-studio.sh                  launcher: prefix setup, XDG links, installer, start
src/apply_extra.sh                       install-time hook for the downloaded installer
data/                                    desktop entry, metainfo (8 translations), MIME type, icon
scripts/upstream.py                      check / update / verify the pinned Studio version
ci/smoke-test.sh                         headless install-and-launch test with screenshot
ci/make-site.sh                          builds the GitHub Pages remote
.github/workflows/                       build.yml, update.yml
```

## Known limitations

- CUDA (GPU) photoreal rendering does not work under Wine; CPU rendering does.
- Wine is fixed at build time. A Wine regression would only arrive with a rebuild, and the smoke
  test is there to catch the obvious cases.
- The published screenshot shows whatever Studio displays on its first start on a clean runner,
  which may include a sign-in or welcome dialog.

## Uninstall

```sh
flatpak uninstall --delete-data io.github.mdarocha.BrickLinkStudio
```

This removes the prefix. Models in your Documents folder stay.

## License

The files in this repository are under the MIT license (see `LICENSE`). The icon is an original
drawing made for this package.

BrickLink Studio is proprietary software by BrickLink, distributed under its own license
agreement, which its installer shows on first start. LEGO is a trademark of the LEGO Group.
