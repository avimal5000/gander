# Releasing Gander

Gander is released as a DMG on GitHub Releases. There is no auto-update (SPEC D48): Gander never uses the network, so a
new version is a new DMG that replaces the app.

A release is built by `scripts/release.sh`, either on your Mac or by the **Release** workflow when you push a `vX.Y.Z`
tag. Without a Developer ID certificate the DMG is only ad hoc signed, so other Macs show a Gatekeeper warning. With
the certificate and Apple credentials it is signed, notarized by Apple, and stapled, so it opens normally.

## One-time setup: signing and notarization (issue #40)

You need the paid Apple Developer Program account (team ID `WNW4M84Z3U`, as in the Xcode project).

1. **Create the certificate.** Xcode → Settings → Accounts → select your team → **Manage Certificates…** → **+** →
   **Developer ID Application**. (Only the account holder can create this type.)
2. **Export it.** Keychain Access → My Certificates → right-click "Developer ID Application: …" → **Export…** → save
   as `gander-developer-id.p12` with a password you choose.
3. **Make an app-specific password.** appleid.apple.com → Sign-In and Security → App-Specific Passwords → **+** → name
   it "Gander notarization".
4. **Put them in the repository's secrets** (Terminal, in the Gander folder; `gh` asks for each value and nothing is
   printed or saved in the shell history):
   ```bash
   base64 -i gander-developer-id.p12 | gh secret set MACOS_CERTIFICATE_P12_BASE64
   gh secret set MACOS_CERTIFICATE_PASSWORD      # the password from step 2
   gh secret set APPLE_ID                        # your Apple ID email
   gh secret set APPLE_APP_SPECIFIC_PASSWORD     # the password from step 3
   gh secret set APPLE_TEAM_ID                   # WNW4M84Z3U
   ```
5. Delete `gander-developer-id.p12` from disk once it is a secret. Keep a copy in a password manager.

Any missing secret just means a less-signed release: the workflow says which kind it built in the release notes.

## Cut a release

1. Make sure `main` is green and holds what you want to ship.
2. Tag and push:
   ```bash
   git checkout main && git pull
   git tag v0.1.0
   git push origin v0.1.0
   ```
3. The Release workflow runs the privacy guard and the tests, builds, signs, notarizes (if the secrets exist), and
   publishes a **pre-release** with the DMG and its `.sha256`. Edit the notes if you want, and untick "pre-release"
   when you are ready for 1.0.
4. A bad release: `gh release delete v0.1.0 --cleanup-tag`, fix, and tag again.
5. **No build started after the tag push?** GitHub skips push-triggered workflows when the tagged commit's message
   contains `[skip ci]`, and a squash merge copies that text from the PR's commits into the commit on `main`. Check
   with `git log -1 --format=%B vX.Y.Z`. Either tag a newer commit, or run the **Release** workflow by hand on the tag
   (Actions → Release → Run workflow → choose the tag). When squash-merging, pass `--body` to keep such markers out.

The version comes from the tag. `MARKETING_VERSION` in the Xcode project only matters for local builds: keep it equal
to the latest release.

## Build locally

```bash
scripts/release.sh                                   # ad hoc signed DMG in dist/
security find-identity -v -p codesigning            # lists your signing identities
APPLE_ID=you@example.com APPLE_APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx APPLE_TEAM_ID=WNW4M84Z3U \
  scripts/release.sh --identity "Developer ID Application: Your Name (WNW4M84Z3U)" --notarize
```

The script also runs `scripts/audit-privacy.sh` on the built app, and fails if the app links a networking library or
has a network entitlement.

The DMG window has a branded background with an arrow from Gander to Applications. `scripts/make-dmg-background.swift`
draws it, and `dmgbuild` lays out the window (`scripts/dmg-settings.py`); keep the icon positions in those two files
in step. The script installs `dmgbuild` into `.build-release/` from `scripts/dmg-requirements.txt`, pinned by hash,
so a build needs network access for that step. It is a build tool only and never ships in Gander. A notarized build
leaves out the "Open Anyway" hint at the bottom of the window.

## What users see

- **Signed and notarized:** open the DMG, drag Gander to Applications, open it. No warning.
- **Ad hoc only:** macOS says Apple could not verify the app. Click **Done** (not Move to Trash), then System
  Settings → Privacy & Security → scroll to Security → **Open Anyway** next to "Gander was blocked", and confirm with
  the password or Touch ID. macOS 15 and later removed the right-click → Open shortcut, so that no longer works.
  Or: `xattr -dr com.apple.quarantine /Applications/Gander.app`, then open Gander.
- **Permissions:** Camera and Accessibility are granted per app signature. A different signature (the Xcode build,
  the ad hoc build, and the Developer ID build are three different ones) asks again, and the old Accessibility
  entry stays in the list: remove it with the **−** button and add the new one. Do this once after switching from
  an Xcode build to an installed release.
- **Login item:** "Open at login" is registered for the app in `/Applications`; run Gander from there.

## Why there is no auto-update

Auto-update needs the network, which would break Gander's promise that it never uses it. If that ever changes, it needs a
new decision, a network entitlement, an updated privacy audit and welcome text, and a library such as Sparkle.
