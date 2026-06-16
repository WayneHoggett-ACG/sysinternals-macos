# Build, Release, and Versioning

This document describes how ZoomIt for macOS is built, versioned, and released.
It follows common open-source and macOS-distribution conventions:
[Semantic Versioning](https://semver.org), trunk-based development,
[Keep a Changelog](https://keepachangelog.com), and tag-driven release
automation.

---

## TL;DR

| Task | Command |
| --- | --- |
| Build the app locally | `make app` |
| Run the test suite | `make test` |
| Build & launch | `make run` |
| See the version a build would stamp | `make version` |
| Package a distributable zip | `make zip` |
| **Cut a release** | `git tag vX.Y.Z && git push origin vX.Y.Z` |

A release is **only** ever produced by pushing a `vX.Y.Z` tag. Pushing
branches, documentation, or workflow changes never publishes a release.

---

## Versioning

Versions follow **Semantic Versioning 2.0.0**: `MAJOR.MINOR.PATCH`, tagged in
git as `vMAJOR.MINOR.PATCH` (e.g. `v1.2.0`).

| Component | Increment when… | Examples |
| --- | --- | --- |
| **MAJOR** | A change breaks backward compatibility | Raising the minimum macOS version; removing or repurposing a default hotkey |
| **MINOR** | Functionality is added in a backward-compatible way | A new capture mode; a new option |
| **PATCH** | A backward-compatible bug fix is made | The panorama blank-region stitching fix |

Pre-releases use a hyphenated suffix (`v1.2.0-rc.1`, `v1.2.0-beta.1`) and sort
*before* the final release, per SemVer precedence rules. Use these when you want
testers to validate a build before the final tag.

### Git tags are the single source of truth

Nothing hardcodes a version. The build derives it at assembly time:

- **`CFBundleShortVersionString`** (the marketing version shown in the About
  dialog) comes from `git describe --tags --abbrev=0`, with the leading `v`
  stripped. On an untagged checkout it falls back to `0.0.0`.
- **`CFBundleVersion`** (the build number) is the commit count
  (`git rev-list --count HEAD`) — monotonically increasing across the history.

Because the version is computed from the tag, the bundle version can never drift
from what was released. Preview it any time with `make version`.

---

## Branching model

**Trunk-based development.** `main` is always in a releasable state.

- Small changes can be committed directly to `main`.
- Larger changes go on short-lived `feature/*` branches, opened as a pull
  request, and squash-merged once CI is green.
- **Releasing is just tagging a commit on `main`** — there are no long-lived
  release branches (no git-flow).

Every push to `main` and every pull request runs CI (tests + a smoke build), so
breakage is caught before it can be tagged.

---

## Building locally

### Prerequisites

- macOS 14 (Sonoma) or later
- Xcode or the Xcode Command Line Tools (provides the Swift toolchain)

### Targets

```sh
make app      # release build, assembled into dist/ZoomIt.app, ad-hoc signed
make test     # swift test (ZoomItCore unit suite)
make run      # build then launch
make zip      # build, then package dist/ZoomIt-<version>.zip via ditto
make version  # print the version/build this checkout would stamp
make clean    # remove build products and dist/
```

By default `make app` builds for the host architecture only (fast). To produce a
**universal** binary (Apple Silicon + Intel), pass `ARCHS`:

```sh
make app ARCHS="arm64 x86_64"
make zip ARCHS="arm64 x86_64"
```

The release pipeline always builds universal so a single download runs natively
on both architectures.

### End-to-end smoke test

Beyond the unit suite, the app bundle can self-test its real status item, hotkey
registration, overlay render pipeline, and break timer:

```sh
./dist/ZoomIt.app/Contents/MacOS/ZoomIt --selftest
```

It prints a pass/fail report and exits non-zero on failure.

---

## Continuous integration

Workflow: [`.github/workflows/ci.yml`](../.github/workflows/ci.yml)

- **Triggers:** push to `main`, and pull requests targeting `main`.
- **Runner:** `macos-15`. This is deliberate — the recorder references
  `SCStreamConfiguration.captureMicrophone`, a macOS 15+ API that is
  runtime-guarded with `#available` but must still compile against the macOS 15
  SDK. Older runner images may ship an SDK that can't compile it.
- **Steps:** `swift test`, then `make app` as a smoke build.
- Concurrent runs on the same ref are cancelled in favor of the newest.

CI is intentionally **not** filtered by path: every change to `main` is built and
tested. A change that looks like "just docs" can still touch the `Makefile`, a
workflow, or a resource, so the safe default is to validate everything.

---

## Releasing

Workflow: [`.github/workflows/release.yml`](../.github/workflows/release.yml)

### The trigger model

The release workflow runs **only** on pushed tags matching `v*`:

```yaml
on:
  push:
    tags:
      - 'v*'
```

This is the guarantee that **ordinary commits — including changes to the CI or
release workflows themselves — never publish a release.** A release happens if
and only if you create and push a version tag.

### Steps to cut a release

1. Make sure `main` is green in CI and has everything you want to ship.
2. Update [`CHANGELOG.md`](../CHANGELOG.md): move items into a new
   `## [X.Y.Z] - YYYY-MM-DD` section.
3. Commit the changelog to `main`.
4. Create an **annotated** tag and push it:
   ```sh
   git tag -a v1.2.0 -m "ZoomIt for macOS 1.2.0"
   git push origin v1.2.0
   ```

### What the automation does

On the tag push, the release workflow (on `macos-15`):

1. Checks out the full history (`fetch-depth: 0`) so `git describe` resolves the
   version.
2. Runs `swift test`.
3. Builds a **universal** app bundle and packages it:
   `make zip ARCHS="arm64 x86_64"`.
4. Verifies the binary contains both architectures (`lipo -archs`).
5. Publishes a GitHub Release for the tag with auto-generated notes and
   `ZoomIt-<version>.zip` attached.

If any step fails, no release is created — so a bad build never results in a
published-but-broken release.

### Watching a release

```sh
gh run list --workflow release.yml --limit 1
gh run watch <run-id> --exit-status
gh release view v1.2.0
```

---

## Changelog and release notes

Two complementary records:

- **[`CHANGELOG.md`](../CHANGELOG.md)** — a hand-curated, human-readable history
  in Keep a Changelog format. This is the canonical "what changed" for readers
  browsing the repo.
- **GitHub Release notes** — generated automatically by `gh release
  --generate-notes` from the commits and merged PRs since the previous tag.

To make the generated notes read well, keep commit subjects and PR titles
descriptive and imperative ("Fix panorama duplicating content…"). Adopting
[Conventional Commits](https://www.conventionalcommits.org) (`feat:`, `fix:`,
`docs:` …) is a reasonable future step that also makes the next version number
obvious from the commit log.

---

## Code signing and distribution

Release binaries are **ad-hoc signed** (`codesign --sign -`), **not** notarized
with an Apple Developer ID. This is a deliberate trade-off (see `Decisions.md`):
it's free, but on first launch macOS Gatekeeper warns that the developer can't be
verified.

Users open a downloaded build the first time by either:

- right-clicking `ZoomIt.app` → **Open** and confirming, or
- clearing the quarantine flag: `xattr -d com.apple.quarantine /Applications/ZoomIt.app`

**Upgrade path:** if the Gatekeeper friction ever becomes a real adoption
barrier, switch to a Developer ID certificate plus Apple notarization (requires a
paid Apple Developer account). Only the signing step and an added notarization
step change; the rest of the pipeline stays the same.

---

## Hotfixes

A hotfix is just a PATCH release: commit the fix to `main`, update the changelog,
and tag `vX.Y.(Z+1)`. There is no separate hotfix branch because `main` is always
the release line.

---

## Rolling back or yanking a release

Releases are immutable by convention — prefer rolling *forward* with a new patch
version over altering history. If a release must be withdrawn (e.g. a broken
artifact slipped through):

```sh
gh release delete v1.2.0 --yes      # remove the GitHub Release + assets
git push origin :refs/tags/v1.2.0   # delete the remote tag
git tag -d v1.2.0                   # delete the local tag
```

Then fix the problem on `main` and cut a new tag (e.g. `v1.2.1`). Avoid reusing a
version number that was ever public.
