#!/usr/bin/env bash
# Seeds GitHub labels, milestones M0-M8, and issues from PLAN.md. Idempotent: existing items are skipped.
# Usage: scripts/seed-github.sh            (REPO defaults to avimal5000/gander)
set -euo pipefail
REPO="${REPO:-avimal5000/gander}"

existing_labels=$(gh label list -R "$REPO" --limit 300 --json name -q '.[].name')
existing_milestones=$(gh api "repos/$REPO/milestones?state=all&per_page=100" -q '.[].title')
existing_issues=$(gh issue list -R "$REPO" --state all --limit 500 --json title -q '.[].title')

label() { # name color description
  if grep -qxF -- "$1" <<<"$existing_labels"; then echo "label exists: $1"; return; fi
  gh label create "$1" -R "$REPO" --color "$2" --description "$3" >/dev/null
  echo "label created: $1"
}

milestone() { # title description
  if grep -qxF -- "$1" <<<"$existing_milestones"; then echo "milestone exists: $1"; return; fi
  gh api "repos/$REPO/milestones" -f title="$1" -f description="$2" >/dev/null
  echo "milestone created: $1"
}

issue() { # milestone title labels(comma-separated) body
  if grep -qxF -- "$2" <<<"$existing_issues"; then echo "issue exists: $2"; return; fi
  local args=(-R "$REPO" --milestone "$1" --title "$2" --body "$4")
  [[ -n "$3" ]] && args+=(--label "$3")
  gh issue create "${args[@]}" >/dev/null
  existing_issues+=$'\n'"$2"
  echo "issue created: $2"
}

# Labels (PLAN.md section 7, plus area/core and area/infra for engine and tooling work)
label "area/camera"  "1D76DB" "Capture, Vision, pose estimation"
label "area/focus"   "5319E7" "Window tracking and focus control"
label "area/ui"      "0E8A16" "Menu bar, windows, onboarding, overlays"
label "area/privacy" "B60205" "Privacy guarantees and audits"
label "area/core"    "006B75" "Calibration, decision engine, pipeline"
label "area/infra"   "C5DEF5" "Build, CI, release, repo automation"
label "risk"         "D93F0B" "Retires one of the PLAN.md risks"
label "spike"        "FBCA04" "Exploratory or measurement work"

M0="M0 Foundations"
M1="M1 Head-pose spike (go/no-go)"
M2="M2 Core engine"
M3="M3 Focus controller"
M4="M4 End-to-end loop"
M5="M5 Calibration + settings"
M6="M6 Design pass"
M7="M7 Hardening"
M8="M8 Release (later)"

milestone "$M0" "Xcode installed; private repo; app + GanderCore skeleton; CI, lint, templates, labels, milestones, issues seeded from PLAN.md."
milestone "$M1" "Debug window shows live yaw/pitch; trace recorder; looking at each display shows clearly separated signals. Decision recorded in the repo. GO/NO-GO gate."
milestone "$M2" "CalibrationModel + SwitchDecider with unit tests over synthetic and recorded traces: no false switches on noise, fast enough on intentional looks."
milestone "$M3" "Per-display last-used window tracking; Accessibility onboarding; 'switch to display N' works from a debug button without moving the cursor."
milestone "$M4" "Menu bar app: camera -> pose -> decider -> focus. Pause/Resume, Focus Lock hotkey, status icon. First daily-driver build."
milestone "$M5" "Guided calibration (layout, camera position, distance), sensitivity settings, recalibrate prompt on display changes."
milestone "$M6" "Forest green / sage / ivory / charcoal theme, icons, onboarding, edge glow, restrained animation, light/dark."
milestone "$M7" "Sleep/wake, lid close, hot-plug, camera conflicts, full-screen/Spaces, CPU/battery targets, privacy audit, multi-hour soak."
milestone "$M8" "Signing, notarization, DMG, release workflow on tag, optional auto-update (Sparkle)."

# M0
issue "$M0" "Xcode app target + GanderCore package skeleton" "area/infra" \
  "Thin SwiftUI menu bar app (LSUIElement) importing the local GanderCore package, one module per area (CONTRACT.md). Builds with xcodebuild; swift test passes."
issue "$M0" "CI: build, test, lint, privacy guard on pull requests" "area/infra,area/privacy" \
  "GitHub Actions macOS runner on pull requests only: swift test (GanderCore), unsigned xcodebuild, swift-format + SwiftLint, scripts/privacy-guard.sh."
issue "$M0" "Issue/PR templates, labels, milestones, seeded issues" "area/infra" \
  "Bug, feature, and calibration-report templates; PR template with privacy/behavior checklist; labels and milestones M0-M8; issues from PLAN.md via scripts/seed-github.sh."
issue "$M0" "Dependabot for GitHub Actions" "area/infra" "Weekly Dependabot updates for workflow action versions."

# M1
issue "$M1" "CameraService: low-res capture, start/stop, sleep/lock aware" "area/camera,area/privacy,spike" \
  "About 640x480 at 10-15 fps, late frames dropped, built-in camera by default with device selection. Session exists only while running; sleep, display sleep, and screen lock tear it down (camera light off) and it resumes after. No frames are stored."
issue "$M1" "PoseEstimator: Vision head pose + landmark-based proxy" "area/camera,spike" \
  "Vision face rectangles + landmarks -> HeadPose(yaw, pitch, roll, faceConfidence) plus a landmark-derived yaw/pitch proxy, so the gate can compare both signals. LivePoseSource combines camera frames and the estimator."
issue "$M1" "Pose debug window: live yaw/pitch/roll, face confidence, fps" "area/ui,spike" \
  "Live numbers, a yaw/pitch plot, camera status and picker, and a live guess of the nearest display after a gate test."
issue "$M1" "Pose trace recorder + replay PoseSource" "spike" \
  "Numeric-only JSON traces (DEBUG builds only) in ~/Library/Application Support/Gander/Traces, ReplayPoseSource and synthetic traces for tests."
issue "$M1" "Guided gate test + separability report" "spike,risk" \
  "Highlight each display in turn, record labeled hold samples over several rounds, then report per-display stats, pairwise d', held-out accuracy, and a GO / MARGINAL / NO-GO verdict for each feature set. Copyable Markdown summary."
issue "$M1" "Record M1 go/no-go decision" "risk" \
  "Run the gate test on the real setup and fill in docs/decisions/0001-m1-head-pose-gate.md. Blocks M2."

# M2
issue "$M2" "CalibrationModel: per-display pose profiles -> P(display | pose) with margin" "area/core" \
  "Per-display pose profiles from calibration samples; posterior over displays with a confidence margin (best vs runner-up). Generic over N displays; MVP limit via GanderPolicy.maxTrackedDisplays."
issue "$M2" "SwitchDecider: dwell, confidence threshold, hysteresis, cooldown, focus lock" "area/core" \
  "Pure state machine. Fires only when the best display beats the runner-up by the margin, the face is clearly detected, dwell completes, and Focus Lock is off. Uncertain = do nothing."
issue "$M2" "Engine tests over synthetic and recorded traces" "area/core" \
  "No false switches on noise and glances; switches promptly on intentional looks. Uses ReplayPoseSource and recorded M1 traces."

# M3
issue "$M3" "WindowTracker: last-used window per display" "area/focus" \
  "Track the last-activated window on each display via NSWorkspace activation + AX window frames; fall back to the topmost window on that display."
issue "$M3" "FocusController: raise + activate target window without moving the cursor" "area/focus,risk" \
  "AXRaise + app activation across apps, Spaces, and full screen on macOS 14+. Never moves the cursor or changes selections."
issue "$M3" "Accessibility permission onboarding" "area/ui,area/focus" "Explain, request, and detect Accessibility trust; deep link to System Settings."
issue "$M3" "Debug: 'switch to display N' button" "area/focus" "Manual trigger to validate focus switching independently of the camera."
issue "$M3" "Document focus fallbacks (Spaces, full-screen, restricted apps)" "area/focus,risk" "Documented fallback list for cases where AX raise or activation is refused."

# M4
issue "$M4" "Tracking pipeline: camera -> pose -> decider -> focus" "area/core" "Wire the end-to-end loop with layout-change and Focus Lock handling."
issue "$M4" "Menu bar status icon states" "area/ui" "Tracking, paused, no face, camera busy, Focus Lock, needs calibration."
issue "$M4" "Pause / Resume tracking" "area/ui,area/privacy" "Pausing stops the camera session (indicator off)."
issue "$M4" "Focus Lock global hotkey (default Control-Option-Command-L)" "area/focus" "Carbon RegisterEventHotKey, configurable, no extra permission."

# M5
issue "$M5" "Guided calibration flow (layout, camera position, distance)" "area/ui,area/core" "Setup under 2 minutes including permissions; recalibration under 30 seconds."
issue "$M5" "Sensitivity settings: dwell delay, thresholds" "area/ui" "UserDefaults-backed settings with sensible defaults."
issue "$M5" "Recalibrate prompt on display layout change" "area/core,area/ui" "Calibrations stored per layout fingerprint + camera; unknown layout pauses tracking and prompts."
issue "$M5" "Camera picker + per-camera calibration" "area/camera" "Choose built-in, external, or Continuity Camera; calibration keyed by camera."

# M6
issue "$M6" "Theme: forest green / sage / ivory / charcoal, light + dark" "area/ui" "Apply the palette across all UI."
issue "$M6" "App icon + menu bar icons" "area/ui" "Replace the placeholder icon; template menu bar glyphs per state."
issue "$M6" "Onboarding flow" "area/ui" "First-run walkthrough: permissions, calibration, Focus Lock."
issue "$M6" "Edge glow on target display (~300 ms)" "area/ui" "Optional thin forest-green edge glow on switch. Silent."
issue "$M6" "Restrained animation pass" "area/ui" "Subtle, purposeful motion only."

# M7
issue "$M7" "Sleep/wake and lid-close handling" "area/camera" "Camera off during sleep/lock/lid close; clean resume."
issue "$M7" "Display hot-plug handling" "area/core" "Connect/disconnect while tracking; stale calibration detection."
issue "$M7" "Camera busy / conflicts degrade gracefully" "area/camera,risk" "Zoom/FaceTime holding the camera: no switches, clear status, auto-recover."
issue "$M7" "Full-screen apps and Spaces behavior" "area/focus,risk" "Verify and document behavior across Spaces and full-screen windows."
issue "$M7" "CPU/battery targets + adaptive throttling" "area/camera,risk" "Measure with Instruments; throttle when face idle/absent."
issue "$M7" "Privacy audit" "area/privacy" "Verify no video written, no network access, camera only while tracking."
issue "$M7" "Multi-hour soak test" "risk" "Daily-driver soak with notes on false switches and resource use."

# M8
issue "$M8" "Signing + notarization" "area/infra" "Developer ID signing and notarization (paid Apple Developer account)."
issue "$M8" "DMG packaging" "area/infra" "Signed DMG for GitHub Releases."
issue "$M8" "Release workflow on v* tags" "area/infra" "Build, sign, notarize, and attach the DMG on tag."
issue "$M8" "Optional auto-update (Sparkle)" "area/infra" "The one dependency PLAN.md would consider."

echo "Seeding complete for $REPO."
