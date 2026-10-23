#!/usr/bin/env python3
"""Keeps the manifest's extra-data entry in sync with BrickLink's published Studio releases.

  upstream.py check            print the newest upstream version; exit 0 either way
  upstream.py update [--version V]
                               point the manifest at the newest (or given) version and add a
                               <release> to the metainfo; also repairs a stale size/checksum
  upstream.py verify           download the installer the manifest points at and check that
                               its size and sha256 match

With GITHUB_OUTPUT set, `check` and `update` also write `version`, `current` and `updated`.
Only the standard library is used, so this runs on any CI runner or dev machine as is.
"""

import argparse
import datetime
import hashlib
import os
import pathlib
import re
import sys
import urllib.request
import xml.sax.saxutils

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP_ID = "io.github.mdarocha.bricklink-studio-flatpak"
MANIFEST = ROOT / f"{APP_ID}.yml"
METAINFO = ROOT / "data" / f"{APP_ID}.metainfo.xml"

VERSION_LIST_URL = "https://studio.download.bricklink.info/Studio2.0/version_Patch_OpenBeta.txt"
INSTALLER_URL = "https://studio.download.bricklink.info/Studio2.0/Archive/{version}/Studio+2.0.exe"
RELEASE_DETAILS_URL = "https://www.bricklink.com/v3/studio/download.page"
VERSION_RE = re.compile(r"\d+\.\d+\.\d+_\d+")
USER_AGENT = "bricklink-studio-flatpak-updater (+https://github.com/mdarocha/bricklink-studio-flatpak)"


def open_url(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": USER_AGENT}), timeout=60)


def fetch_releases():
    """Returns [(version, date or None, [release notes])] in the order BrickLink lists them, oldest first."""
    with open_url(VERSION_LIST_URL) as response:
        text = response.read().decode("utf-8-sig", "replace")

    # Line prefixes: "0" version, "4" date as YY.M.D.n, "1"-"3" release notes.
    releases = []
    for line in text.splitlines():
        line = line.strip()
        # Entries below this marker belong to a separate, frozen release track.
        if line == "All-In-One Version":
            break
        if m := re.fullmatch(r"0 (\S+)", line):
            releases.append([m[1], None, []])
        elif releases and releases[-1][1] is None and (m := re.fullmatch(r"4 (\d+)\.(\d+)\.(\d+)(?:\.\d+)?", line)):
            year, month, day = map(int, m.groups())
            releases[-1][1] = datetime.date(2000 + year, month, day)
        elif releases and (m := re.fullmatch(r"[1-3] (.+)", line)):
            releases[-1][2].append(m[1])
    return [(v, d, notes) for v, d, notes in releases if VERSION_RE.fullmatch(v)]


def read_extra_data():
    """Returns (manifest text, block text, {url, sha256, size}) for the single extra-data source."""
    text = MANIFEST.read_text()
    m = re.search(r"^(?P<indent>[ ]*)- type: extra-data\n(?:(?P=indent)  .*\n)+", text, re.MULTILINE)
    if not m:
        sys.exit(f"no extra-data source found in {MANIFEST.name}")
    block = m[0]
    fields = {key: re.search(rf"^\s+{key}: (\S+)$", block, re.MULTILINE)[1] for key in ("url", "sha256", "size")}
    fields["size"] = int(fields["size"])
    return text, block, fields


def version_from_url(url):
    m = re.search(r"/Archive/([^/]+)/", url)
    return m[1] if m else None


def download_digest(url):
    """Streams the file and returns (sha256 hex, size in bytes)."""
    digest, size = hashlib.sha256(), 0
    with open_url(url) as response:
        while chunk := response.read(1 << 20):
            digest.update(chunk)
            size += len(chunk)
    return digest.hexdigest(), size


def write_outputs(**values):
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a") as f:
            for key, value in values.items():
                f.write(f"{key}={value}\n")


def add_release(version, date, notes):
    text = METAINFO.read_text()
    if f'<release version="{version}"' in text:
        return
    m = re.search(r"^(?P<indent>[ ]*)<releases>\n", text, re.MULTILINE)
    if not m:
        sys.exit(f"no <releases> element in {METAINFO.name}")
    pad = m["indent"] + "  "
    date_attr = f' date="{date.isoformat()}"' if date else ""
    entry = f'{pad}<release version="{version}"{date_attr}>\n'
    entry += f'{pad}  <url type="details">{RELEASE_DETAILS_URL}</url>\n'
    if notes:
        items = "".join(f"{pad}      <li>{xml.sax.saxutils.escape(note)}</li>\n" for note in notes)
        entry += f"{pad}  <description>\n{pad}    <ul>\n{items}{pad}    </ul>\n{pad}  </description>\n"
    entry += f"{pad}</release>\n"
    METAINFO.write_text(text[: m.end()] + entry + text[m.end() :])


def cmd_check(_args):
    latest = fetch_releases()[-1][0]
    _, _, fields = read_extra_data()
    current = version_from_url(fields["url"])
    print(f"upstream: {latest}\nmanifest: {current}")
    write_outputs(version=latest, current=current, updated="false")


def cmd_update(args):
    releases = {v: (d, notes) for v, d, notes in fetch_releases()}
    version = args.version or list(releases)[-1]
    if not VERSION_RE.fullmatch(version):
        sys.exit(f"not a Studio version: {version}")

    text, block, fields = read_extra_data()
    current = version_from_url(fields["url"])
    url = INSTALLER_URL.format(version=version)

    # size 0 marks a checksum taken from a third party that was never downloaded and measured here.
    if current == version and fields["size"] > 0 and not args.force:
        print(f"manifest already at {version}")
        write_outputs(version=version, current=current, updated="false")
        return

    print(f"downloading {url}")
    sha256, size = download_digest(url)
    new_block = block
    for key, value in (("url", url), ("sha256", sha256), ("size", size)):
        new_block = re.sub(rf"^(\s+{key}: )\S+$", lambda m: f"{m[1]}{value}", new_block, count=1, flags=re.MULTILINE)
    MANIFEST.write_text(text.replace(block, new_block))
    add_release(version, *releases.get(version, (None, [])))

    print(f"manifest: {current} -> {version} (sha256 {sha256}, {size} bytes)")
    write_outputs(version=version, current=current, updated="true")


def cmd_verify(_args):
    _, _, fields = read_extra_data()
    if fields["size"] <= 0:
        sys.exit("extra-data size is not set; run `scripts/upstream.py update` first")
    print(f"downloading {fields['url']}")
    sha256, size = download_digest(fields["url"])
    if (sha256, size) != (fields["sha256"], fields["size"]):
        sys.exit(
            f"mismatch: manifest has sha256 {fields['sha256']} / {fields['size']} bytes, "
            f"upstream serves {sha256} / {size} bytes"
        )
    print("installer matches the manifest")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("check").set_defaults(func=cmd_check)
    update = sub.add_parser("update")
    update.add_argument("--version", help="Studio version to pin, e.g. 2.26.9_1 (default: newest)")
    update.add_argument("--force", action="store_true", help="re-download and re-hash even if already current")
    update.set_defaults(func=cmd_update)
    sub.add_parser("verify").set_defaults(func=cmd_verify)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
