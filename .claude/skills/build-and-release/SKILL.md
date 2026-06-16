---
name: build-and-release
description: >-
  Build, version, and release ZoomIt for macOS. Use this whenever the user wants
  to build the app, run the tests, cut or publish a release, tag a new version,
  bump the version number, or ship a build to GitHub Releases — including terse
  asks like "release", "ship it", "cut a new version", "publish a build", or
  "how do I release this". Covers the tag-driven release workflow (SemVer
  tagging, the Makefile targets, watching the GitHub Actions run, verifying the
  published artifact) and how to roll a release back. Trigger for any
  build/release/versioning task in this repository, even when the user doesn't
  name a specific command.
---

# Build and Release

This repo ships ZoomIt for macOS as downloadable binaries on GitHub Releases.
The process is **tag-driven**: pushing a `vX.Y.Z` tag is the single act that
builds and publishes a release. Everything else is local convenience.

The authoritative reference is [`docs/BUILD_AND_RELEASE.md`](../../../docs/BUILD_AND_RELEASE.md).
Read it when you need the full rationale, the CI/runner details, or anything not
covered below. This skill is the operational checklist.

## Mental model (the invariants that keep you out of trouble)

- **Git tags are the single source of truth for the version.** The build derives
  `CFBundleShortVersionString` from `git describe` and `CFBundleVersion` from the
  commit count. Never hardcode a version anywhere — change the tag instead.
- **Releases fire only on `v*` tags.** Pushing branches, docs, or even edits to
  the workflows themselves never publishes a release. So you can refactor CI
  freely; a release happens if and only if you push a version tag.
- **`main` is always releasable.** Development is trunk-based. Tagging is done on
  `main`.
- **Release builds are universal** (arm64 + x86_64) and **ad-hoc signed** (not
  notarized), so downloaders hit a one-time Gatekeeper prompt — that's expected,
  not a bug.

## Building and testing locally

Use these for development and to sanity-check before tagging. None of them
publish anything.

```sh
make test                      # swift test — the ZoomItCore unit suite
make app                       # assemble dist/ZoomIt.app (host arch, ad-hoc signed)
make run                       # build then launch
make version                   # print the version/build this checkout would stamp
make zip                       # build + package dist/ZoomIt-<version>.zip
make app ARCHS="arm64 x86_64"  # universal build (what the release pipeline does)
```

After `make app`, the bundle can self-test its real status item, hotkeys,
overlay rendering, and break timer:

```sh
./dist/ZoomIt.app/Contents/MacOS/ZoomIt --selftest
```

It exits non-zero on failure, so it's safe to gate on in scripts.

## Cutting a release

Follow these steps in order. Don't skip the pre-flight — a release built from a
red `main` wastes a version number.

### 1. Decide the version bump (SemVer)

Pick the next `vMAJOR.MINOR.PATCH` based on what changed since the last tag:

- **MAJOR** — a breaking change (raising the minimum macOS version, changing a
  default hotkey contract).
- **MINOR** — a new backward-compatible feature (a new mode or option).
- **PATCH** — a backward-compatible bug fix.

Check the latest released tag with `gh release list` or `git tag --sort=-v:refname | head`.

### 2. Pre-flight

- Ensure everything you want to ship is merged to `main`.
- Confirm CI is green on the head of `main`:
  ```sh
  gh run list --workflow ci.yml --branch main --limit 1
  ```
  If it isn't green, stop and fix that first.

### 3. Update the changelog

Move the relevant items in [`CHANGELOG.md`](../../../CHANGELOG.md) into a new
`## [X.Y.Z] - YYYY-MM-DD` section (use today's date). Commit it to `main`. This
keeps the in-repo history curated; the GitHub Release notes are generated
separately from commit messages.

### 4. Tag and push

Create an **annotated** tag (annotated, not lightweight, so it carries a message
and date) and push it:

```sh
git tag -a vX.Y.Z -m "ZoomIt for macOS X.Y.Z"
git push origin vX.Y.Z
```

Before pushing, you can confirm the tag resolves to the version you expect:
`git checkout <tag> 2>/dev/null; make version` — or just trust `git describe`.

### 5. Watch the release run

The push triggers [`.github/workflows/release.yml`](../../../.github/workflows/release.yml).
Find and watch it to completion:

```sh
gh run list --workflow release.yml --limit 1
gh run watch <run-id> --exit-status
```

The workflow runs the tests, builds the universal bundle, verifies both
architectures with `lipo`, and publishes the GitHub Release with the zip
attached. If any step fails, no release is created — so a failed run leaves you
free to fix and re-tag rather than with a broken published release.

### 6. Verify

```sh
gh release view vX.Y.Z --json name,tagName,isDraft,url,assets \
  --jq '{name,tagName,isDraft,url,assets:[.assets[]|{name,size}]}'
```

Confirm `isDraft` is `false` and `ZoomIt-X.Y.Z.zip` is attached.

## Rolling back a release

Prefer rolling **forward** with a new patch version over rewriting history. If a
release genuinely must be withdrawn (e.g. a bad artifact slipped through):

```sh
gh release delete vX.Y.Z --yes      # remove the GitHub Release + assets
git push origin :refs/tags/vX.Y.Z   # delete the remote tag
git tag -d vX.Y.Z                   # delete the local tag
```

Then fix `main` and cut a new tag (e.g. the next patch). Don't reuse a version
number that was ever public.

## Notes on outward-facing actions

Tagging, pushing, publishing, and deleting releases are public and hard to
reverse. Confirm the version number and that `main` is in the intended state
before pushing a tag, and surface what you're about to do rather than tagging
silently.
