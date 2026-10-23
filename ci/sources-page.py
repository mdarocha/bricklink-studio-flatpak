#!/usr/bin/env python3
"""Writes the HTML source list for everything the published Flatpak contains.

Usage: ci/sources-page.py APP_MANIFEST BASE_MANIFEST REPO_URL GIT_COMMIT > sources.html
  APP_MANIFEST   /app/manifest.json from the built app (flatpak-builder's resolved manifest)
  BASE_MANIFEST  /app/manifest-base-1.json, the resolved manifest of the Wine base app
  REPO_URL       https://github.com/OWNER/REPO, for this repository's own local sources
  GIT_COMMIT     commit the app was built from
"""

import html
import json
import sys

WINE_RECIPE_URL = "https://github.com/flathub/org.winehq.Wine/tree/branch/{branch}"


def source_link(source, local_base):
    kind = source.get("type", "")
    if kind == "git":
        ref = source.get("commit") or source.get("tag") or source.get("branch", "")
        return f'<a href="{html.escape(source["url"])}">{html.escape(source["url"])}</a> at <code>{html.escape(ref)}</code>'
    if "url" in source:
        checksum = source.get("sha256", "")
        suffix = f" <small>sha256 <code>{html.escape(checksum)}</code></small>" if checksum else ""
        return f'<a href="{html.escape(source["url"])}">{html.escape(source["url"])}</a>{suffix}'
    if "path" in source:
        url = f"{local_base}/{source['path']}"
        return f'<a href="{html.escape(url)}">{html.escape(source["path"])}</a>'
    return html.escape(kind)


def module_rows(modules, local_base, skip_types=()):
    rows = []
    for module in modules:
        if isinstance(module, str):
            continue
        links = [source_link(s, local_base) for s in module.get("sources", []) if s.get("type") not in skip_types]
        if links:
            rows.append(f"<tr><td>{html.escape(module['name'])}</td><td>{'<br>'.join(links)}</td></tr>")
        rows.extend(module_rows(module.get("modules", []), local_base, skip_types))
    return rows


def table(rows):
    return "<table>\n<tr><th>Module</th><th>Sources</th></tr>\n" + "\n".join(rows) + "\n</table>"


def main():
    app_path, base_path, repo_url, commit = sys.argv[1:5]
    with open(app_path) as f:
        app = json.load(f)
    with open(base_path) as f:
        base = json.load(f)

    base_branch = app["base-version"]
    wine_recipe = WINE_RECIPE_URL.format(branch=base_branch)
    own_rows = module_rows(app["modules"], f"{repo_url}/blob/{commit}", skip_types=("extra-data",))
    base_rows = module_rows(base["modules"], wine_recipe.replace("/tree/", "/blob/"))

    print(f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Sources – BrickLink Studio Flatpak</title>
<link rel="icon" href="icon.svg">
<style>
  body {{ font-family: system-ui, sans-serif; max-width: 60rem; margin: 2rem auto; padding: 0 1rem; line-height: 1.5; }}
  table {{ border-collapse: collapse; width: 100%; }}
  td, th {{ border-bottom: 1px solid #ccc; padding: .3rem .5rem; text-align: left; vertical-align: top; overflow-wrap: anywhere; }}
  @media (prefers-color-scheme: dark) {{ body {{ background: #1b1b1b; color: #ddd; }} a {{ color: #8ab4f8; }} td, th {{ border-color: #444; }} }}
</style>
</head>
<body>
<p><a href="./">← BrickLink Studio (unofficial Flatpak)</a></p>
<h1>Sources</h1>
<p>The Flatpak published here is built from the sources below, generated from the build's own
resolved manifests. BrickLink Studio itself is not part of it: Flatpak downloads Studio's installer
from BrickLink's servers on your machine when you install the app.</p>

<h2>This package</h2>
<p>Built from <a href="{html.escape(repo_url)}/tree/{html.escape(commit)}">{html.escape(repo_url)} at
<code>{html.escape(commit)}</code></a>.</p>
{table(own_rows)}

<h2>Wine</h2>
<p>Wine and its tools are copied in from Flathub's <code>{html.escape(app["base"])}</code> base app,
branch <code>{html.escape(base_branch)}</code>, OSTree commit <code>{html.escape(app.get("base-commit", "unknown"))}</code>.
Its build recipe is <a href="{html.escape(wine_recipe)}">flathub/org.winehq.Wine</a>, and Flathub publishes
its complete sources as <code>flatpak install flathub {html.escape(app["base"])}.Sources//{html.escape(base_branch)}</code>.</p>
{table(base_rows)}

<h2>Runtime</h2>
<p>The app runs on <code>{html.escape(app["runtime"])}//{html.escape(app["runtime-version"])}</code>, which Flatpak
installs from Flathub; it is not redistributed here.</p>
</body>
</html>""")


if __name__ == "__main__":
    main()
