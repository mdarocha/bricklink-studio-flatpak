#!/bin/bash
# Assembles the GitHub Pages site that serves the Flatpak remote.
#
# Usage: ci/make-site.sh REPO_DIR SITE_DIR BASE_URL GPG_KEY_ID
#   REPO_DIR    signed OSTree repo produced by flatpak-builder
#   SITE_DIR    output directory; screenshots/ may already exist inside it
#   BASE_URL    public URL of the site, without a trailing slash
#   GPG_KEY_ID  key whose public half clients pin via the .flatpakrepo/.flatpakref files
set -euo pipefail

repo_dir=$1
site=$2
base_url=$3
key_id=$4
app=io.github.mdarocha.BrickLinkStudio
remote=bricklink-studio
here=$(cd "$(dirname "$0")/.." && pwd)

mkdir -p "$site"
cp -a "$repo_dir" "$site/repo"
cp "$here/data/$app.svg" "$site/icon.svg"
# Pages would otherwise run Jekyll over the repo and skip files starting with "_" or ".".
touch "$site/.nojekyll"

gpg_key=$(gpg --export "$key_id" | base64 -w0)

cat >"$site/$remote.flatpakrepo" <<EOF
[Flatpak Repo]
Title=BrickLink Studio (unofficial)
Url=$base_url/repo/
Homepage=$base_url/
Comment=Unofficial Flatpak of BrickLink Studio
Description=Runs the official Windows version of BrickLink Studio with Wine. The installer is downloaded from BrickLink at install time.
Icon=$base_url/icon.svg
DefaultBranch=stable
GPGKey=$gpg_key
EOF

cat >"$site/$app.flatpakref" <<EOF
[Flatpak Ref]
Name=$app
Branch=stable
Title=BrickLink Studio (unofficial)
Url=$base_url/repo/
SuggestRemoteName=$remote
RuntimeRepo=https://dl.flathub.org/repo/flathub.flatpakrepo
IsRuntime=false
Icon=$base_url/icon.svg
GPGKey=$gpg_key
EOF

screenshot=""
if [[ -f "$site/screenshots/main.png" ]]; then
    screenshot="<img src=\"screenshots/main.png\" alt=\"BrickLink Studio main window\">"
fi

cat >"$site/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>BrickLink Studio Flatpak</title>
<link rel="icon" href="icon.svg">
<style>
  body { font-family: system-ui, sans-serif; max-width: 46rem; margin: 2rem auto; padding: 0 1rem; line-height: 1.5; }
  pre { background: #f2f2f2; padding: .75rem; overflow-x: auto; }
  img { max-width: 100%; border: 1px solid #ccc; }
  @media (prefers-color-scheme: dark) { body { background: #1b1b1b; color: #ddd; } pre { background: #2a2a2a; } a { color: #8ab4f8; } }
</style>
</head>
<body>
<h1><img src="icon.svg" alt="" width="48" height="48" style="border:0;vertical-align:middle"> BrickLink Studio (unofficial Flatpak)</h1>
<p>Runs the official Windows version of BrickLink Studio with Wine. Flatpak downloads Studio's installer
from BrickLink's servers when you install the app; this site only hosts Wine and the launcher scripts.
Not affiliated with BrickLink or the LEGO Group.</p>
<h2>Install</h2>
<p>Needs the Flathub remote for the runtime. Then either open
<a href="$app.flatpakref">$app.flatpakref</a> with GNOME Software or Discover, or run:</p>
<pre>flatpak remote-add --user --if-not-exists $remote $base_url/$remote.flatpakrepo
flatpak install --user $remote $app</pre>
$screenshot
<p>Source and documentation: <a href="https://github.com/mdarocha/bricklink-studio-flatpak">github.com/mdarocha/bricklink-studio-flatpak</a></p>
</body>
</html>
EOF

echo "site assembled in $site"
