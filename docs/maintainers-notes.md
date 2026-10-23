# Maintainer notes

## Packaging

- **Wine** comes from Flathub's `org.winehq.Wine` base app (branch `stable-25.08`, Wine 11.0,
  with winetricks). It is copied into this app at build time.
- **32-bit libraries** for Wine's 32-bit half (Studio's installer is 32-bit) come from Flathub's
  `org.freedesktop.Platform.Compat.i386`, also copied in at build time. Flatpak installs an app's
  extensions only from the app's own remote, so users of this remote would never get Flathub's.
  Wine Mono and Gecko are left out for the same reason; Studio needs neither, and
  `WINEDLLOVERRIDES` stops Wine from offering to download them.
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

Flatpak can't install a single-file bundle of an extra-data app
([flatpak/flatpak#1334](https://github.com/flatpak/flatpak/issues/1334)), so test builds are
installed from an OSTree repo instead:

```sh
flatpak-builder --repo=repo --default-branch=stable --force-clean build-dir io.github.mdarocha.BrickLinkStudio.yml
flatpak remote-add --user --no-gpg-verify local-build repo
flatpak install --user local-build io.github.mdarocha.BrickLinkStudio
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
| Build / build | same | Builds in the Flathub `freedesktop-25.08` container and uploads the OSTree repo as an artifact. On main: signs commits, regenerates the summary and appstream data. |
| Build / smoke-test | same | Runs `nix run .#smoke-test` on that repo (see below). |
| Build / deploy | main only | Publishes the signed OSTree repo, `.flatpakrepo`, `.flatpakref`, icon, screenshot and a landing page to GitHub Pages. |
| Check for Studio updates | Mondays, dispatch | Opens an update PR as described above. |
| Verify actions lockfile | every push to main, PR | Runs `gh actions-lock --verify`. |

The metainfo screenshot URL points at the screenshot the smoke test publishes, so the store listing
shows the real app without any BrickLink images being stored in this repository. If a smoke test
fails, the deploy keeps the previously published screenshot.

### Smoke test

`ci/smoke-test.sh`, packaged as a flake app, installs the app from an OSTree repo, starts it with
an unattended install in a headless GNOME Shell (Wayland, Studio on Xwayland), declines the Unity
Analytics consent dialog, dismisses the tutorial banner and saves a window screenshot the way
GNOME's own screenshot tool does: title bar, rounded corners and shadow on a transparent
background, 1000x700, default GNOME settings. Nix provides everything except the app, so a local
run matches CI:

```sh
flatpak-builder --repo=repo --default-branch=stable --force-clean build-dir io.github.mdarocha.BrickLinkStudio.yml
nix run .#smoke-test -- repo smoke-test
```

It uses a throwaway `HOME`, so it downloads the Flathub runtime each time and doesn't touch your
Flatpak installation. The result is `smoke-test/main.png`; on failure, `failure.png` shows the
whole screen. Studio's installer takes about 5 minutes on a desktop and over 30 on a GitHub runner.

The extension in `ci/smoke-test/` gives the script a D-Bus API on GNOME Shell to place, click and
capture the window. Click positions are offsets from the centre of Studio's client area at
1000x700; if a Studio update moves the consent dialog's buttons, the test fails waiting for the
consent step to complete, and `failure.png` shows where they went.

### Action pinning

Workflows reference actions by full release tag. `.github/workflows/actions.lock` pins each one,
including transitive dependencies, to a commit; GitHub refuses to run a workflow whose `uses:` has
no entry there. After changing any `uses:`, regenerate it with the
[gh-actions-lock](https://github.com/github/gh-actions-lock) extension:

```sh
gh extension install github/gh-actions-lock
gh actions-lock
```

Dependabot bumps actions weekly and updates the lockfile in the same PR. The build container is
pinned by digest, which neither tool updates; refresh it by hand when changing the runtime:
`skopeo inspect --format '{{.Digest}}' docker://ghcr.io/flathub-infra/flatpak-github-actions:freedesktop-25.08`.

## Layout

```
io.github.mdarocha.BrickLinkStudio.yml   Flatpak manifest
src/bricklink-studio.sh                  launcher: prefix setup, XDG links, installer, start
src/apply_extra.sh                       install-time hook for the downloaded installer
data/                                    desktop entry, metainfo (8 translations), MIME type, icon
scripts/upstream.py                      check / update / verify the pinned Studio version
ci/smoke-test.sh                         headless install-and-launch test with screenshot (flake app)
ci/smoke-test/extension.js               GNOME Shell extension the smoke test drives the window through
ci/make-site.sh                          builds the GitHub Pages remote
.github/workflows/                       build.yml, update.yml, verify-lockfile.yml, actions.lock
```

## Known limitations

- Wine is fixed at build time. A Wine regression would only arrive with a rebuild, and the smoke
  test is there to catch the obvious cases.
- The published screenshot shows BrickLink's live "Featured" content as of the last smoke test.
