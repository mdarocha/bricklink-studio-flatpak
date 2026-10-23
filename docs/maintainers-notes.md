# Maintainer notes

## Packaging

- **Wine** comes from Flathub's `org.winehq.Wine` base app (branch `stable-26.08`, Wine 11.0,
  with winetricks). It is copied into this app at build time.
- **64-bit only.** Wine's 32-bit side would need a copy of Flathub's i386 runtime (Flatpak
  installs an app's extensions only from the app's own remote), which doubled the download.
  Studio and innoextract don't need it; the launcher works around the one place winetricks
  expects it. Wine Mono and Gecko are left out for the same reason; Studio needs neither, and
  `WINEDLLOVERRIDES` stops Wine from offering to download them.
- **Studio** is an `extra-data` source: the manifest holds only the URL of the installer in
  BrickLink's versioned archive, its size and its sha256. Flatpak downloads and verifies it at
  install time and puts it in `/app/extra`.
- **innoextract** unpacks that installer into the Wine prefix in about half a minute; running it
  under Wine took over ten. The installer is Inno Setup 6.7, which no innoextract release reads, so
  the manifest builds the head of the upstream PR
  [dscharrer/innoextract#205](https://github.com/dscharrer/innoextract/pull/205), pinned by commit
  and checksum and reviewed, plus `patches/innoextract-studio.patch`. The patch keeps the 728 empty
  files that branch skips and adds `--show-license`, which prints the license agreement the
  launcher shows before the first install. Besides its files the installer only creates shortcuts,
  writes three Windows GPU-timeout registry values and offers to start Studio; none of that
  applies under Wine, and its `[Code]` only runs on uninstall. If a Studio release moves to an
  Inno Setup version the pinned innoextract can't read, the smoke test of the update PR fails.
- **Wine patch.** The manifest rebuilds the base app's `dxgi.dll` and `wined3d.dll` from the same
  Wine release with `patches/wine-unity-video.patch`
  ([wine/wine!11398](https://gitlab.winehq.org/wine/wine/-/merge_requests/11398), not yet merged).
  With `WINE_D3D_CONFIG=no_create_flags=0x800` from the finish-args, it fails Unity's
  video-decoding D3D11 device, so Unity decodes in software and the welcome screen's tutorial video
  plays instead of an empty box. The build fails if the base app moves to another Wine release;
  then update the source URL and checksum, check that the patch still applies, and drop it once
  Wine implements `IDXGIResource::GetSharedHandle`.

## Licensing

- Studio is never redistributed: it's an `extra-data` source, so only its URL, size and checksum
  are in the published repo, and each user's Flatpak downloads it from BrickLink. CI downloads it
  to check the checksum and to run the smoke test (BrickLink's license allows internal testing),
  but uploads only logs and the screenshot, and deletes the Flatpak installation before the Nix
  cache is saved.
- The launcher shows the license agreement embedded in the installer and installs only after the
  user accepts it. `STUDIO_UNATTENDED_INSTALL=1` skips the dialog and is meant for CI.
- The published repo redistributes Wine and its tools (LGPL/GPL) and innoextract (zlib).
  `ci/sources-page.py` generates `sources.html` on the Pages site from the manifests
  flatpak-builder embeds in the app, so the list always matches what was built.
- The app icon and file icon are original drawings, not BrickLink artwork. The store screenshot
  shows Studio's UI, including BrickLink's "Featured" banners at the time of the smoke test.

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
    build-dir io.github.mdarocha.bricklink-studio-flatpak.yml
flatpak run io.github.mdarocha.bricklink-studio-flatpak
```

`--install-deps-from` pulls the Freedesktop 26.08 runtime and the Wine base app. The build compiles
a static Boost and innoextract, which takes a few minutes. The installer is downloaded during
`--install`, not during the build.

Flatpak can't install a single-file bundle of an extra-data app
([flatpak/flatpak#1334](https://github.com/flatpak/flatpak/issues/1334)), so test builds are
installed from an OSTree repo instead:

```sh
flatpak-builder --repo=repo --default-branch=stable --force-clean build-dir io.github.mdarocha.bricklink-studio-flatpak.yml
flatpak remote-add --user --no-gpg-verify local-build repo
flatpak install --user local-build io.github.mdarocha.bricklink-studio-flatpak
```

### Checking metadata

```sh
appstreamcli validate --no-net data/io.github.mdarocha.bricklink-studio-flatpak.metainfo.xml
desktop-file-validate data/io.github.mdarocha.bricklink-studio-flatpak.desktop
podman run --rm -v "$PWD:/w:Z" -w /w ghcr.io/flathub/flatpak-builder-lint:latest \
    manifest io.github.mdarocha.bricklink-studio-flatpak.yml
```

The linter reports `runtime-update-available` when a new Freedesktop runtime is out. Flathub
wouldn't accept this app anyway: it only takes Wine-wrapped Windows apps from their upstream.

## Updates

`.github/workflows/update.yml` runs every Monday. `scripts/upstream.py` reads BrickLink's version
list (`version_Patch_OpenBeta.txt`, the same source winget's updater uses), and if there is a newer
release it downloads the installer from
`https://studio.download.bricklink.info/Studio2.0/Archive/<version>/Studio+2.0.exe`, measures its
size and sha256, rewrites the manifest's extra-data entry and adds a `<release>` with BrickLink's
release notes to the metainfo.
It then opens a PR and starts the Build and lockfile workflows on that branch; Build installs the
result and starts Studio. Merge when it is green; main publishes to the remote.

Run it by hand from the Actions tab ("Check for Studio updates"), optionally pinning a version,
or locally with `python3 scripts/upstream.py update [--version 2.26.9_1]`.

## CI

| Workflow / job | Runs on | Does |
|---|---|---|
| Build / verify-upstream | every push, PR, dispatch | Downloads the installer the manifest points at and checks size and sha256. |
| Build / build | same | Builds in the Flathub `freedesktop-26.08` container and uploads the OSTree repo as an artifact. On main: signs commits, regenerates the summary and appstream data. |
| Build / smoke-test | same | Runs `nix run .#smoke-test` on that repo (see below). |
| Build / deploy | main only | Publishes the signed OSTree repo, `.flatpakrepo`, `.flatpakref`, icon, screenshot and a landing page to GitHub Pages. |
| Check for Studio updates | Mondays, dispatch | Opens an update PR as described above. |
| Verify actions lockfile | every push to main, PR, dispatch | Runs `gh actions-lock --verify`. |

The `default` ruleset on main requires a PR with every review thread resolved, and the checks
"Check installer URL, size and checksum", "Build Flatpak", "Install, start Studio and take a
screenshot" and "Verify actions lockfile". Repository admins can bypass it.

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
flatpak-builder --repo=repo --default-branch=stable --force-clean build-dir io.github.mdarocha.bricklink-studio-flatpak.yml
nix run .#smoke-test -- repo smoke-test
```

It uses a throwaway `HOME`, so it downloads the Flathub runtime each time and doesn't touch your
Flatpak installation. The result is `smoke-test/main.png`; on failure, `failure.png` shows the
whole screen. Studio's first start (Wine prefix, core fonts, innoextract) took about 3 minutes on a
desktop, about 4 for the whole test.

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
`skopeo inspect --format '{{.Digest}}' docker://ghcr.io/flathub-infra/flatpak-github-actions:freedesktop-26.08`.

## Layout

```
io.github.mdarocha.bricklink-studio-flatpak.yml   Flatpak manifest
src/bricklink-studio.sh       launcher: license prompt, prefix setup, XDG links, innoextract, start
src/apply_extra.sh            install-time hook for the downloaded installer
data/                         desktop entry, metainfo (8 translations), MIME type, app and file icons
patches/                      innoextract patch for Studio's installer, Wine patch for its videos
scripts/upstream.py           check / update / verify the pinned Studio version
ci/smoke-test.sh              headless install-and-launch test with screenshot (flake app)
ci/smoke-test/extension.js    GNOME Shell extension the smoke test drives the window through
ci/make-site.sh               builds the GitHub Pages remote
.github/workflows/            build.yml, update.yml, verify-lockfile.yml, actions.lock
```

## Known limitations

- Wine is fixed at build time. A Wine regression would only arrive with a rebuild, and the smoke
  test is there to catch the obvious cases.
- The published screenshot shows BrickLink's live "Featured" content as of the last smoke test.
