# Foreground issue: switching brought other windows forward

Date: 2026-11-02, hardened 2026-11-04. Status: fixed for Chrome, partly fixed for Terminal.

## The problem

When Gander switched focus to the window you looked at, other windows of the same app sometimes came forward with it,
on other monitors.

Example setup:

- **Left monitor:** a Chrome window.
- **Middle monitor:** Terminal on top of a second Chrome window.

Looking at the left Chrome focused it, but the middle Chrome also jumped over Terminal. The same happened with
Terminal: looking at the Terminal on the right monitor brought the laptop's Terminal over iTerm.

## Root causes

Gander's live logs showed two separate causes.

### 1. Chrome: the fallback brought every window forward

Gander focuses a window in two steps: raise the window, then activate its app. If focus isn't confirmed within 300 ms, it
falls back to the Accessibility "frontmost" call, which brings **every** window of the app forward.

Every switch to the left Chrome window went through that fallback (`method=accessibilityFrontmost`, about 360 ms).
That is how the middle Chrome ended up over Terminal.

### 2. Terminal: it brings back the window last typed in

The normal activation (`NSRunningApplication.activate(options: [])`) brings forward the app's main window **and** its
key window. Gander makes the target the main window, but the key window is still the one you last typed in.

About 60 to 150 ms after a switch, Terminal itself moves typing focus back to that window and brings it forward, even
when it's on another monitor. Gander then saw focus on that monitor and switched straight back, so focus bounced back
and forth.

## The solution

### Front-window-only activation (SPEC D53)

Gander now activates the app with Carbon's `SetFrontProcessWithOptions(kSetFrontProcessFrontWindowOnly)`. This brings
forward only the app's front window (the target Gander just raised), the same way a click on that window would.

- The function is public but deprecated, and Swift can't call it, so it lives in a small C target:
  `GanderCore/Sources/FrontProcess`.
- If the call is refused or missing, or the app isn't frontmost within 100 ms, Gander falls back to the old activation.
- The Carbon calls are weak imports, so a future macOS without them still launches Gander and takes that fallback.
- Result: on your Mac every switch used front-window-only, and none needed a fallback. Chrome now brings only the
  window you look at.

### Keep focus on the window looked at (SPEC D54)

200 ms and 500 ms after a confirmed switch, Gander checks the app again. If the app is still in front but has moved
focus to one of its own windows on another monitor, Gander raises the target again. Focus that moved within the
monitor is left alone, so a new window (⌘N) or a sheet keeps it. This runs in the background, and the next switch
cancels it.

This stops the back-and-forth switching that Terminal's behavior caused.

### No switch on the screen already in use (SPEC D52)

Just before switching, Gander checks the window you're actually working in. If it's already on the target monitor
(assigned there, or covering at least a quarter of it), Gander raises nothing. It logs "Already in &lt;app&gt; on
&lt;display&gt;" and shows no edge glow.

Without this check, two things could raise a buried window over the one in use:

- the once-a-second focus check is out of date (the Instant timing fires right away);
- the window spans two monitors.

## What was tried and dropped

- **Raising the covered window back.** After a switch, Gander raised the window that had been on top (for example
  iTerm) back over the one the app had brought forward. Dropped: iTerm makes itself the active app when one of its
  windows is raised, which caused focus to bounce back and forth.
- **Making the target the key window before activating.** Setting `kAXFocusedWindowAttribute` before activation had no
  effect: Terminal still brought its other window forward.

## Known limit

Terminal still brings its last-typed-in window forward over whatever covered it, even though focus stays on the window
you looked at. No public macOS API puts one app's window behind another app's window.

A click on another monitor's window of the same app within 0.5 s of a switch is undone once: Gander can't tell it from
the app moving focus, and reading input events is ruled out by the privacy guard.

## Files changed

- `GanderCore/Sources/FrontProcess/`: new C target with `GanderFrontWindowOnly(pid)`.
- `GanderCore/Package.swift`: adds the C target as a dependency of FocusControl.
- `GanderCore/Sources/FocusControl/LiveFocusPlatform.swift`: front-window-only activation, with the old activation as
  the fallback.
- `GanderCore/Sources/FocusControl/AXFocusController.swift`: the already-focused check and the keep-focus follow-up.
- `GanderCore/Sources/FocusControl/AlreadyFocusedCheck.swift`, `KeepFocusCheck.swift`, `FrontWindowActivation.swift`: new,
  with tests.
- `GanderCore/Sources/GanderModels/Focus.swift`: new `FocusMethod.alreadyFocused`.
- `TrackingLoop.swift`, `AppModel+Tracking.swift`, and the two presentation files: handle "already focused" (no edge
  glow, its own log line, and the display is held like an override).
- `SPEC.md` (D52 to D54), `CONTRACT.md`, and `docs/focus-fallbacks.md`.
- `scripts/privacy-guard.sh` (now scans C too), `scripts/release.sh` (fails on a strong Carbon import), and
  `scripts/soak.sh` (reports fallbacks and focus kept).

## Checks

- **Passed on 2026-11-04:** all package tests (1,381), swift-format lint, the privacy guard, the unsigned Debug build, and
  an ad-hoc Release build with its DMG and privacy audit.
- **Weak imports:** both architectures of the Release binary import the Carbon calls weakly. With the real C file linked
  to a stand-in library, removing the symbols left the program running with `unimpErr`; a strong build died in dyld.
- **Tested by hand on 2026-11-02:** in the Xcode build, on three monitors, with Chrome, Terminal and iTerm. That run was
  before the 2026-11-04 changes to keep-focus and the already-focused check.

## Before a release

1. **Repeat the hand test.** On three monitors with Chrome, Terminal and iTerm, and add ⌘N right after a switch.
2. **Run the soak** (`scripts/soak.sh`). "activation fallbacks" and "via the frontmost call" should stay near zero.
3. **Run the signed build.** This Mac has no Developer ID certificate, so signing and notarization only run in the
   release workflow.
