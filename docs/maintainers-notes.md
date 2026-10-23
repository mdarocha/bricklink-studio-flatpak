# Maintainer notes

## Packaging

- **Wine** comes from Flathub's `org.winehq.Wine` base app (branch `stable-25.08`, Wine 11.0,
  with winetricks). It is copied into this app at build time.
- **Studio** is an `extra-data` source: the manifest holds only the URL of the installer in
  BrickLink's versioned archive, its size and its sha256. Flatpak downloads and verifies it at
  install time and puts it in `/app/extra`.

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

- Wine is fixed at build time. A Wine regression would only arrive with a rebuild, and the smoke
  test is there to catch the obvious cases.
- The published screenshot shows whatever Studio displays on its first start on a clean runner,
  which may include a sign-in or welcome dialog.
