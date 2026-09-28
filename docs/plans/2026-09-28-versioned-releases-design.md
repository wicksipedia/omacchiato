# Versioned releases

## Goal

Today `omacchiato-update` pulls the tip of the tracked branch, and
`install.sh` builds every binary on the user's Mac. After this change,
the update moves the clone to the newest release tag, and `install.sh`
downloads the binaries that the release carries. A local build stays
for a clone that has its own edits.

Scope: GitHub releases only, Apple silicon only. No App Store, no
Developer ID, no notarization.

## Decisions

- **Signing identity.** Sign the release with the maintainer's
  Apple Development certificate. The designated requirement of the bar
  today is:

  ```
  identifier "com.omacchiato.bar" and anchor apple generic and
  certificate leaf[subject.CN] = "Apple Development: Matthew Wicks (UBFFH7VF9B)"
  and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */
  ```

  The requirement names the certificate by its subject, not by its
  hash. So a renewed certificate with the same name keeps the TCC
  grants.
- **No quarantine.** A browser marks a download with
  `com.apple.quarantine`, and Gatekeeper then refuses a binary that
  Apple did not notarize. `curl` does not set the mark. Download
  releases only with `curl`, and tell users not to download the asset
  in a browser.
- **Version.** Tags are dates on `main`: `vYYYY.MM.DD`. A second
  release on the same day is `vYYYY.MM.DD.1`, then `.2`. The first
  release counts as `.0`. The tag is the
  only record of the version. No version file goes in the repo.
- **Build machine.** Build on the maintainer's Mac first (phase 1).
  Move to GitHub Actions only when the release script is stable
  (phase 3).

## What the release holds

One asset per release, plus a checksum file:

```
omacchiato-vYYYY.MM.DD-arm64.tar.gz
  omacchiato-bar.app
  omacchiato-gesture.app
  omacchiato-helper
  omacchiato-overview
  omacchiato-omni
SHA256SUMS
```

`airpods-control` and tokscale stay as they are. `install.sh` fetches
them at a pinned version and checks a pinned hash.

## Phase 1: build and publish from the maintainer's Mac

1. **Move the build commands out of `install.sh`** into
   `bin/omacchiato-build <out-dir>`. It builds the five binaries into
   `<out-dir>` and signs them if an Apple Development identity exists.
   `install.sh` calls it for a local build, so the local build and the
   release build use the same commands. Keep the "rebuild only when a
   source changed" checks in `install.sh`.
2. **Add `bin/omacchiato-release`.** It picks the next date version. It refuses to run
   unless:
   - the tree is clean,
   - `HEAD` is `origin/main`,
   - the tag does not exist,
   - `bin/omacchiato-test` passes.

   Then it:
   1. runs `omacchiato-build` into a temporary folder,
   2. checks each signature with `codesign --verify --strict` and the
      requirement in "Checks on the user's Mac" below,
   3. reuses the gesture app of the previous release if nothing in
      `helper/gesture/` changed since that tag (see "The gesture
      daemon"),
   4. writes the tarball and `SHA256SUMS`,
   5. creates and pushes the tag,
   6. runs `gh release create <version> <tarball> SHA256SUMS
      --generate-notes`.
3. **Add a test** in `tests/` for the part of the release script that
   picks the previous tag and decides whether the gesture app changed.

## Phase 2: install and update from a release

1. **`install.sh` picks a source for the binaries:**
   - If `git describe --exact-match --tags` names a `v*` tag, and the
     tree is clean, download the asset for that tag with `curl -fL`.
   - Otherwise, or if any step of the download fails, build locally.
     Print which source it used.
2. **Checks before the binaries are copied** (see below). A failed
   check stops the download path and falls back to a local build. It
   never installs the binaries that failed.
3. **Do not sign again on the user's Mac.** A release binary keeps the
   signature it came with. `install.sh` signs only what it built.
4. **`omacchiato-update` follows tags.** It fetches tags from the
   remote that the branch tracks, takes the newest `v*` tag
   (`git tag --sort=-v:refname`), and fast-forwards the local branch to
   that tag with `git merge --ff-only`. The branch stays `main`, so the
   current checks (local changes, ahead, diverged) still apply.
   `omacchiato-update --edge` keeps the old behaviour: pull the branch
   tip and build locally.
5. **`omacchiato-updates` (the pill)** compares the local `HEAD` with
   the newest tag, not with the branch tip. The popup lists the commits
   between the two.
6. **Existing installs.** The first update to a release changes the
   signature of the bar, the helper and the overview from the user's own
   certificate to the maintainer's certificate. Each of them then needs
   its grants again, one time. `omacchiato-permissions` already runs at
   the end of `omacchiato-update`. Say so in the notes of the first
   release.

## Checks on the user's Mac

1. `shasum -a 256 -c SHA256SUMS` for the tarball.
2. After the tarball is extracted, check each binary:

   ```sh
   codesign --verify --strict -R='anchor apple generic and certificate leaf[subject.OU] = "V66SHHUE58"' <path>
   ```

   The checksum comes from the same place as the tarball, so it shows
   only that the download is complete. The requirement shows that the
   maintainer's team signed the binary. The team ID (`V66SHHUE58`) is
   the `TeamIdentifier` that `codesign -dv` prints, not the ID in the
   certificate name. Keep it in one variable in `install.sh`.

## The gesture daemon

TCC pins the Accessibility grant of `omacchiato-gesture` to the exact
build. A new build, even from the same source, can differ. Two rules
keep the grant:

- The release script copies the gesture app from the previous release
  when `git diff --quiet <previous-tag> HEAD -- helper/gesture` is true.
- `install.sh` replaces the installed gesture app only when its
  CDHash differs from the one in the release
  (`codesign -dv --verbose=4 2>&1 | grep CDHash`).

When the gesture source changes, the release notes must say that
Accessibility and Input Monitoring need a new grant.

## Phase 3: GitHub Actions (optional)

A workflow runs `bin/omacchiato-release` on `macos-26` when someone
starts it by hand (`workflow_dispatch`). It needs:

- the Apple Development certificate and its key, exported as a `.p12`,
  in a secret, with its password in a second secret,
- a temporary keychain on the runner that holds the certificate,
- `contents: write` permission for the tag and the release.

The secret gives anyone with write access to the workflow a way to
sign code that gets the users' grants. Limit it to a protected
environment that needs the maintainer's approval.

## Risks

- **Private frameworks.** The binaries link SkyLight,
  DisplayServices, Sharing and MultitouchSupport. A binary built on a
  newer macOS can fail on an older one. Build on the oldest macOS that
  Omacchiato supports.
- **Swift runtime.** Build with the Swift that ships with the
  Command Line Tools of that macOS.
- **Signing key.** If the key leaks, someone can sign code that gets
  the users' grants. Keep it in the login keychain in phase 1 and in a
  protected environment in phase 3.
- **Certificate expiry.** An Apple Development certificate expires after
  one year. Renew it before the next release. The subject stays the
  same, so the grants stay. Not yet tested: whether `codesign --verify` rejects
  an old release after the certificate expires. If it does, install.sh
  builds from source. Signing the release with `--timestamp` may fix it.
- **Forks.** A fork has no releases, or has releases signed with a
  different certificate. The requirement check fails, and `install.sh`
  builds locally. The team ID variable lets a fork change the check.
- **Upstream merges.** Upstream tags, if any, are not ours. Fetch tags
  only from the remote that the branch tracks.

## Open questions

- Does `--edge` stay after the move, or does it go away after some
  releases?
