# Focus fallbacks (M3)

How Sway gives keyboard focus to the last-used window on a display, what it does when that fails, and the
known limits. PLAN.md risk 2: macOS 14+ restricts cross-app activation. Implemented in `FocusControl`
(CONTRACT §6.7). Tracks issue #18.

## How the target window is chosen

The **last-used window on a display** is its topmost normal window in the window server's front-to-back order
(`CGWindowListCopyWindowInfo`, on-screen only). macOS keeps that order by recency of use, so no observers or
history are needed. A normal window means all of the following:

- layer 0 (excludes menus, the Dock, panels, and overlays);
- visible (alpha > 0.01);
- at least 120×80 pt;
- not Sway's own;
- not owned by Window Server, Dock, or WindowManager.

A window belongs to the display holding most of its area.

## The fallback list

Each step is verified before Sway reports success: the target app must be frontmost, and the target window must
be its focused window. Verification polls every 25 ms, for up to 300 ms per step.

| Step | What Sway does | Notes |
|---|---|---|
| 0 | Not trusted → stop with "Accessibility permission needed" | Nothing is attempted without permission |
| 1 | No normal window on the display → "No window on <display>" | Sway never launches or un-minimizes anything |
| 2 | Find the window through Accessibility by matching its frame (within 2 pt). If the app has exactly one window, use that one | Fails for apps without standard AX windows |
| 3 | **Accessibility raise:** `AXRaise` on the window, `AXMain` on the window, `AXFrontmost` on its app | Primary method; works from a background app because Accessibility bypasses cooperative activation |
| 4 | **App activation:** `NSRunningApplication.activate(from:options:)`, then raise again | Fallback for apps that ignore `AXFrontmost` |
| 5 | Report "Failed: Focus did not move to <app>" | Logged with the app name and timing, never the window title |

Every Accessibility call has a 0.5 s timeout per app and runs off the main thread, so an unresponsive app
cannot freeze Sway.

## What Sway never does

- Move the cursor, click, or synthesize keystrokes.
- Use private window-server APIs.
- Read window contents.

CI enforces all three (`scripts/privacy-guard.sh`).

## Known limits

From the implementation (FocusControl builder report). The last column is filled in from the user's Focus
Test results.

| Situation | Expected behavior | Verified on the user's Mac |
|---|---|---|
| Normal windows, different apps on each display | Focused via Accessibility raise | Pending |
| Two windows of the same app on different displays | The right window is raised (closest frame match) | Pending |
| **Spaces:** last-used window is on another Space of that display | Only the visible Space's windows are listed, so that display gets its topmost window on the current Space, or "No window". Sway never switches Spaces | Pending |
| **Full-screen app** on a display | Listed while its Space is visible and usually focusable. Apps exposing few AX windows can fail the frame match → "Window not found through Accessibility" | Pending |
| **Window spanning two displays** | Belongs to the display with most of its area (tie: the one holding its center). The other display gets its next window, or none | Pending |
| **Minimized or hidden windows** | Never candidates; a display with only those gives "No window". Sway never unminimizes or unhides | Pending |
| **Apps that ignore `AXFrontmost` / `AXRaise`** (some Electron, Java, sandboxed apps) | They report success without moving; verification catches it. The app-activation fallback uses macOS 14 cooperative activation, which the system honors mainly when Sway itself is active. So after "Focus in 3 s" from another app it is effectively a second raise → "Failed: Focus did not move to <app>" after about 650 ms | Pending |
| **Non-standard AX windows** (custom-drawn, Qt/Java/Electron trees, many same-size windows or tab windows) | Frame match can fail or pick a sibling; the closest match wins | Pending |
| **Unresponsive app** | Accessibility reads time out (0.5 s per call) → "Window not found through Accessibility". Sway stays responsive | Pending |
| **Sheet, panel, or palette** is the app's focused window | The raise works but verification sees a different focused window → reported as failed | Pending |
| Sway's own windows (Focus Test window) | Excluded from targets and from the focused-display readout | Pending |

## If verification fails often

The next things to try (M4/M7), in order:

1. Also set `AXFocused = true` on the window after the raise.
2. Accept the pid match when the focused window is a sheet or panel of the target window.
3. Report "did not respond" separately from "window not found" for hung apps.
