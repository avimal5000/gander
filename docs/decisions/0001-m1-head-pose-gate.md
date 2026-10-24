# 0001: M1 head-pose go/no-go gate

- Status: **Pending**. Run the gate test on the real setup, then fill this in.
- Milestone: M1 Head-pose spike (go/no-go)
- Related: PLAN.md section 5 risk 1, SPEC.md section 8

## Question

Does head pose alone (Vision yaw/pitch, or the landmark-derived proxy) separate the displays on the real
setup clearly enough to build M2 (CalibrationModel + SwitchDecider) on it?

## How it was measured

Sway > Head-Pose Gate Test: for each display and round, look at the highlighted display's center; samples
from the hold phase are labeled with that display. The analysis reports per-display stats, pairwise d′, and
held-out nearest-centroid accuracy for each feature set. Thresholds are in CONTRACT.md section 6.3.

## Result

<!-- Paste "Copy Markdown Summary" output here. -->

## Decision

<!-- GO / MARGINAL (what to change) / NO-GO (what instead, e.g. eye gaze). -->
