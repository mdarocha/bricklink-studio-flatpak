#!/usr/bin/env sh
# Runs once at install/update time inside /app/extra, after Flatpak has downloaded
# and checksummed the installer. No network, no display.
set -eu

test -s Studio+2.0.exe

# The launcher compares this with what it last installed into the prefix to
# decide whether the installer needs to run again after an app update.
sha256sum Studio+2.0.exe | cut -d' ' -f1 > installer.sha256
