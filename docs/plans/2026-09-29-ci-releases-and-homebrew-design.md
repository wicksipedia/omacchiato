# Releases from GitHub Actions, and a Homebrew tap

Status: plan. It follows `2026-09-28-versioned-releases-design.md`, where
`bin/omacchiato-release` builds and publishes on this Mac.

## Part A: publish from GitHub Actions

### What is true now

- `macos-26` and `macos-latest` are arm64 runners (GitHub's runner
  table). The test workflow already runs on `macos-26`.
- `bin/omacchiato-release` does the whole job: tests, build, sign,
  verify the team ID, tarball, `SHA256SUMS`, `gh release create`. It
  refuses to run unless the tree is clean and `HEAD` is `origin/main`,
  which a checkout of `main` in CI meets.
- The bar, overview and helper keep their TCC grants because the
  designated requirement names the certificate (its common name), not
  the build. The gesture
  daemon's grant is pinned to its build, and the release reuses the last
  release's gesture app while `helper/gesture/` is the same.

### The workflow

`.github/workflows/release.yml`:

- Trigger: `workflow_dispatch` only. A release starts when you press
  the button.
- `environment: release`, with you as a required reviewer and `main` as
  the only allowed branch. The signing secrets belong to that
  environment, so no other job can read them.
- `runs-on: macos-26`, `permissions: contents: write`,
  `concurrency: release`.
- Steps:
  1. `actions/checkout` with `fetch-depth: 0`, so the tags are there for
     the version number and the gesture comparison.
  2. Select a pinned Xcode with `xcode-select`, and print
     `swift --version` into the log.
  3. Make a temporary keychain, import the certificate from
     `APPLE_DEV_CERT_P12` (base64) with `APPLE_DEV_CERT_PASSWORD`, run
     `security set-key-partition-list` so `codesign` can use the key
     without a prompt, and add the keychain to the search list.
  4. Run `bin/omacchiato-release` with `GH_TOKEN: ${{ github.token }}`.
  5. In an `if: always()` step, delete the keychain.

### Changes to the release script

- Add `--dry-run`: build, sign and verify, then stop before
  `gh release create`. Run it in CI first, and keep it for checks.
- Print the Swift version into the release notes, so a build can be
  traced to its toolchain.

### Things to watch

- The private key lives in GitHub. Anyone who can change the workflow
  on `main` can sign as you. The environment reviewer is the guard.
- The certificate expires each year. Upload the new `.p12` when you
  renew it. A renewed certificate keeps the same common name, so the
  bar, overview and helper keep their grants.
- The runner's Swift differs from yours. The first CI build of the
  gesture app asks every user for Accessibility again, as any gesture
  change does. After that, build releases only in CI, so the toolchain
  stays the same.
- Keep the local path. `bin/omacchiato-release` still works on this Mac
  when CI is down.

## Part B: a Homebrew tap

### What Homebrew allows

| Question | Answer | Source |
| --- | --- | --- |
| Does a cask download get quarantined? | Yes. Checked on this Mac: the OmniWM zip, the Claude and Codex casks. | docs.brew.sh/Homebrew-Security-and-Supply-Chain |
| Does a formula download get quarantined? | No. 0 of 26 formula downloads on this Mac carry the mark. | local check |
| Can a cask skip quarantine? | `--no-quarantine` is deprecated since Homebrew 5.0, as a way around Gatekeeper. | brew.sh/2025/11/12/homebrew-5.0.0 |
| Can a formula depend on a cask? | No: "Unsupported special dependency :cask". | github.com/Homebrew/brew/issues/17326 |
| Can a formula write to `$HOME` while it installs? | No. The install runs in a sandbox that allows writes to its prefix only. | Formula Cookbook |
| Can a formula run two launch agents? | No. A formula has one `service do` block. | Homebrew::Service docs |
| Anything new for taps? | Homebrew 6 asks the user to trust a tap before it runs its code. | brew.sh/2026/06/11/homebrew-6.0.0 |

### Formula, not cask

Our apps carry an Apple Development signature and are not notarized. A
cask download is quarantined, so Gatekeeper blocks the bar and the
gesture daemon at their first launch. The only way around that is to
strip the quarantine in the cask, which Homebrew treats as working
around macOS security. A formula download is not quarantined, which is
the same position as today's `curl` download.

### The shape

- Tap: `wicksipedia/homebrew-omacchiato`. Install with
  `brew install wicksipedia/omacchiato/omacchiato`.
- The release publishes a second asset, `omacchiato-<version>.tar.gz`:
  the repository at the tag (`git archive`) plus the prebuilt binaries.
  The formula downloads it, checks its SHA-256, and puts it in
  `libexec`. `/opt/homebrew/opt/omacchiato` points at it and stays the
  same path across upgrades.
- `depends_on arch: :arm64`, the macOS 26 minimum, and the command-line
  tools from the Brewfile (fzf, eza, zoxide, ripgrep, bat, lazygit,
  btop, starship, jq, gh).
- Homebrew cannot set up the user's session, so the formula links one
  command, `omacchiato`, and its caveats say to run `omacchiato setup`.
  `setup` is today's `install.sh`: it runs `brew bundle` for the casks
  (OmniWM, Karabiner-Elements, Ghostty, Raycast, the font), writes the
  launch agents, the Karabiner rules and the defaults, and asks for the
  permissions.

### Changes to install.sh

- A packaged mode, when the tree is under the Homebrew prefix:
  - The launch agents and links point at the `opt` path, not the
    Cellar path, so an upgrade does not break them.
  - Configs are copied, not linked. Homebrew replaces the tree on
    upgrade, so an edit to a linked file would be lost. The copy mode
    for a clone in `~/Documents` already does this.
  - No build and no download: the binaries are in the tree.
- `omacchiato-update` in packaged mode runs
  `brew upgrade omacchiato`, then `omacchiato setup`.

### Risks to test before the first tap release

- Homebrew can rewrite a Mach-O file in a keg when it relocates it, and
  then signs it again ad hoc. That would drop our signature and every
  TCC grant. Our binaries link only system frameworks, so no rewrite
  should happen. The formula's `test do` block runs
  `codesign --verify -R=<requirement>` on each binary to catch it.
- The binaries move from `~/.local/share/omacchiato` to the Homebrew
  path. The bar, overview and helper keep their grants. Test whether
  the gesture daemon, whose grant is pinned to its build, keeps it at
  the new path.
- Move an existing git-clone install to the formula: `setup` finds the
  old clone, points the agents at the new path, and leaves the clone in
  place for the user to delete.

## Order of work

1. `--dry-run` in `bin/omacchiato-release`.
2. `release.yml`, the `release` environment and its secrets. Run it
   with `--dry-run`, then publish the first CI release.
3. The full-tree asset in the release.
4. The packaged mode in `install.sh`, the `omacchiato` command, and
   `omacchiato-update` in packaged mode.
5. The tap repository and the formula. Test a clean install and an
   upgrade on this Mac.
6. A second job in `release.yml` that updates the formula's URL and
   SHA-256 in the tap. It needs a token that can push to the tap
   repository only.
7. The README install section: Homebrew first, the git clone second.
