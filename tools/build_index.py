#!/usr/bin/env python3
"""Build site/data/index.json, the mod index feed the launcher's FIND MODS tab reads.

gen1recomp's index consumer (src/mods/ModIndex.lua) takes a source as
"owner/repo" and looks for a schema_version 1 feed at

    https://<owner>.github.io/<repo>/data/index.json          (GitHub Pages)
    https://raw.githubusercontent.com/<owner>/<repo>/main/site/data/index.json

the second being the mirror it falls back to when the first fails, which is
also what makes this feed work with Pages switched off entirely.

An index is metadata only -- it lists mods that live in their authors' own
repos, and every install still goes through the same zip import an
"Import mod .zip" does.  This one lists exactly one mod: this one.

manifest.json is the source of truth for everything the manifest already
says.  What is left over -- the blurb, categories and tags a listing needs and
a manifest has no field for -- is LISTING below.

    python3 tools/build_index.py            # rewrite the feed
    python3 tools/build_index.py --check    # CI: fail if it is out of date
"""

import json
import pathlib
import sys
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "manifest.json"
FEED = ROOT / "site" / "data" / "index.json"
RELEASE_WORKFLOW = ROOT / ".github" / "workflows" / "release.yml"

# The launcher's own category vocabulary, in its own order; a feed lists the
# whole set and the panel shows the ones its mods actually use.
CATEGORIES = [
    "GAMEPLAY", "CONTENT", "BALANCE", "ART", "AUDIO", "UI",
    "QOL", "TRANSLATION", "TOTAL_CONVERSION", "LIBRARY", "TOOL", "OTHER",
]

# The listing-only fields.  summary is the card blurb (200 characters is the
# index schema's ceiling); tags are lowercase, 24 characters at most.
LISTING = {
    "summary": "Autosaves on a play-time timer and after battles, catches and "
               "new areas, with optional rollback backups.",
    "categories": ["QOL", "GAMEPLAY"],
    "tags": ["autosave", "save", "quality of life", "backups", "rollback"],
    "license": "MIT",
}


def slug(github):
    owner, _, repo = github.partition("/")
    if not owner or not repo:
        raise SystemExit(f"manifest github {github!r} is not owner/repo")
    return owner, repo


def build():
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    owner, repo = slug(manifest["github"])
    mod_id = manifest["id"]
    raw = f"https://raw.githubusercontent.com/{owner}/{repo}/main"

    entry = {
        "folder": f"{owner}@{mod_id}",
        "id": mod_id,
        "title": manifest["name"],
        "author": manifest["author"],
        "version": manifest["version"],
        "summary": LISTING["summary"],
        "categories": LISTING["categories"],
        "tags": LISTING["tags"],
        "repo": f"https://github.com/{owner}/{repo}",
        "github": manifest["github"],
        "license": LISTING["license"],
        "api": manifest["api"],
        "game_version": manifest["game_version"],
        "profile": manifest["profile"],
        "affects_link": manifest["affects_link"],
        "permissions": [],
        "dependencies": manifest.get("dependencies", []),
        "conflicts": manifest.get("conflicts", []),
        "thumbnail": f"{raw}/site/data/thumbnail.png",
        "description_url": f"{raw}/site/data/description.md",
        # A fixed asset name every release also carries, so "latest" keeps
        # resolving to the newest one without this file being rewritten.
        # Absolute, so a description and a download both work whether or not
        # Pages is serving.
        "downloadURL": f"https://github.com/{owner}/{repo}"
                       f"/releases/latest/download/{mod_id}.zip",
        # No nightly job stands behind a self-published feed, so no release
        # check has been made; the installer falls through to downloadURL.
        "update_check": "pending",
    }

    return {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc)
            .strftime("%Y-%m-%dT%H:%M:%SZ"),
        "count": 1,
        "categories": CATEGORIES,
        "mods": [entry],
    }


def check_release_asset(mod_id):
    """The feed's downloadURL is only a live link while the release workflow
    keeps publishing a fixed-name copy of the archive.  Drop that copy and
    FIND MODS starts 404ing on install, quietly, a release later -- so the two
    files are checked against each other rather than trusted to stay in step.
    """
    text = RELEASE_WORKFLOW.read_text(encoding="utf-8")
    problems = []
    if f'MOD_ID: "{mod_id}"' not in text:
        problems.append(f'release.yml does not set MOD_ID to "{mod_id}"')
    if '"$out/${MOD_ID}.zip"' not in text:
        problems.append("release.yml no longer builds the fixed-name "
                        f"{mod_id}.zip the feed's downloadURL points at")
    if '"dist/${MOD_ID}.zip"' not in text:
        problems.append(f"release.yml no longer uploads {mod_id}.zip")
    return problems


def main(argv):
    check = "--check" in argv[1:]
    feed = build()
    text = json.dumps(feed, indent=2, ensure_ascii=False) + "\n"

    if not check:
        FEED.parent.mkdir(parents=True, exist_ok=True)
        FEED.write_text(text, encoding="utf-8")
        print(f"wrote {FEED.relative_to(ROOT)} "
              f"({feed['mods'][0]['id']} {feed['mods'][0]['version']})")
        return 0

    if not FEED.exists():
        print(f"::error::{FEED.relative_to(ROOT)} is missing; "
              "run python3 tools/build_index.py")
        return 1

    # generated_at is a timestamp, not a fact about the mod: comparing it would
    # make every check fail a second after the last build.
    have = json.loads(FEED.read_text(encoding="utf-8"))
    want = dict(feed)
    have.pop("generated_at", None)
    want.pop("generated_at", None)
    if have != want:
        print(f"::error::{FEED.relative_to(ROOT)} is out of date with "
              "manifest.json; run python3 tools/build_index.py and commit it")
        return 1
    problems = check_release_asset(feed["mods"][0]["id"])
    for problem in problems:
        print(f"::error::{problem}")
    if problems:
        return 1

    print(f"{FEED.relative_to(ROOT)} matches manifest.json "
          f"({feed['mods'][0]['id']} {feed['mods'][0]['version']})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
