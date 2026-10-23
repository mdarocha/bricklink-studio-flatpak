> ⚠️ **100% vibecoded codebase**

# BrickLink Studio Flatpak

Unofficial Flatpak of [BrickLink Studio](https://www.bricklink.com/v3/studio/main.page), the brick
model designer. It runs the official Windows build with Wine, fully inside the Flatpak sandbox:
no Wine on the host, no shared `~/.wine` prefix, no stray `.desktop` files.

BrickLink Studio itself is not stored in this repository or the published Flatpak repo; Flatpak
downloads the installer from BrickLink's servers on your machine when you install the app.

Not affiliated with, endorsed or supported by BrickLink or the LEGO Group.

## How it works

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
- **`.io` files** get their own file icon and open in Studio from the file manager.

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

New Studio releases are picked up weekly and arrive with `flatpak update`. Studio's own in-app
updater still works inside the prefix, but updates through the Flatpak are the ones that stick
across reinstalls.

## Known limitations

- CUDA (GPU) photoreal rendering does not work under Wine; CPU rendering does.

## Uninstall

```sh
flatpak uninstall --delete-data io.github.mdarocha.BrickLinkStudio
```

This removes the prefix. Models in your Documents folder stay.

## License

The files in this repository are under the MIT license (see `LICENSE`). The app and file icons are
original drawings made for this package.

BrickLink Studio is proprietary software by BrickLink, distributed under its own license
agreement, which its installer shows on first start. LEGO is a trademark of the LEGO Group.

Building from source and maintenance notes: [docs/maintainers-notes.md](docs/maintainers-notes.md).
