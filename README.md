> ⚠️ **100% vibecoded codebase**

# BrickLink Studio Flatpak

Unofficial Flatpak of [BrickLink Studio](https://www.bricklink.com/v3/studio/main.page), the brick
model designer. It runs the official Windows build with Wine, fully inside the Flatpak sandbox:
no Wine on the host, no shared `~/.wine` prefix, no stray `.desktop` files.

BrickLink Studio itself is not stored in this repository or the published Flatpak repo; Flatpak
downloads the installer from BrickLink's servers on your machine when you install the app.

Not affiliated with, endorsed or supported by BrickLink or the LEGO Group.

## How it works

- **First start** shows BrickLink's license agreement. Once you accept it, the app creates a
  private Wine prefix in `~/.var/app/io.github.mdarocha.bricklink-studio-flatpak/data/prefix`,
  installs the MS core fonts and unpacks Studio from BrickLink's installer, with a progress window
  for each step. This takes a few minutes.
- **App updates** ship a new installer; on the next start the launcher notices it changed and
  unpacks it over the existing install.
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
flatpak install --user bricklink-studio io.github.mdarocha.bricklink-studio-flatpak
```

After the remote is added the app also shows up in GNOME Software and KDE Discover, and updates
arrive with `flatpak update`. The landing page at
<https://mdarocha.github.io/bricklink-studio-flatpak/> has a one-click `.flatpakref` as well.

## Options

Set with `flatpak override --user --env=NAME=value io.github.mdarocha.bricklink-studio-flatpak`:

| Variable | Effect |
|---|---|
| `STUDIO_DPI` | Windows DPI, applied on every start. `144` = 150 %, `192` = 200 %. Wine defaults to 96, which is tiny on 4K screens. |
| `STUDIO_VIRTUAL_DESKTOP` | e.g. `3840x2160`. Runs Studio inside a Wine virtual desktop window. Use it if dialogs lose focus or alt-tab freezes Studio. |
| `STUDIO_UNATTENDED_INSTALL` | `1` installs silently, accepting BrickLink's license agreement without showing it. Meant for CI. |

Wine tools work through `--command`:

```sh
flatpak run --command=winecfg io.github.mdarocha.bricklink-studio-flatpak
flatpak run --command=winetricks io.github.mdarocha.bricklink-studio-flatpak <verb>
```

## Updates

New Studio releases are picked up weekly and arrive with `flatpak update`. Studio's own in-app
updater still works inside the prefix, but updates through the Flatpak are the ones that stick
across reinstalls.

## Known limitations

- CUDA (GPU) photoreal rendering does not work under Wine; CPU rendering does.

## Uninstall

```sh
flatpak uninstall --delete-data io.github.mdarocha.bricklink-studio-flatpak
```

This removes the prefix. Models in your Documents folder stay.

## Support

BrickLink doesn't support this package, so please don't contact them about it.

- Problems with the packaging, such as installing, the first start, Wine, folders, `.io` files or
  a Studio feature that works on Windows but not here: [open an issue](https://github.com/mdarocha/bricklink-studio-flatpak/issues/new/choose)
  with the output of `flatpak run io.github.mdarocha.bricklink-studio-flatpak` from a terminal.
- Problems with Studio itself, such as bugs that also happen on Windows, your BrickLink account,
  parts or the gallery: BrickLink's [Studio Help Center](https://studiohelp.bricklink.com/hc/en-us)
  and forum.

## License

The files in this repository are under the MIT license (see `LICENSE`), except the patches in
`patches/`: the innoextract patch is under innoextract's zlib license and the Wine patch under
Wine's LGPL-2.1-or-later. The app and file icons are original drawings made for this package. The
published Flatpak also contains Wine and innoextract; the
[sources page](https://mdarocha.github.io/bricklink-studio-flatpak/sources.html) lists the exact
sources of everything in it.

BrickLink Studio is proprietary software by BrickLink, distributed under its own license
agreement, which the app shows on first start. LEGO is a trademark of the LEGO Group.

Building from source and maintenance notes: [docs/maintainers-notes.md](docs/maintainers-notes.md).
