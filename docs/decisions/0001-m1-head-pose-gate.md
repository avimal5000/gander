# 0001: M1 head-pose go/no-go gate

- Status: **Accepted: GO** (2026-10-24)
- Milestone: M1 Head-pose spike (go/no-go)
- Related: PLAN.md section 5 risk 1, SPEC.md section 8, issue #10

## Question

Does head pose alone (Vision yaw/pitch, or the landmark-derived proxy) separate the displays on the real
setup clearly enough to build M2 (CalibrationModel + SwitchDecider) on it?

## How it was measured

Gander > Head-Pose Gate Test: for each display and round, look at the highlighted display's center; samples
from the hold phase are labeled with that display. The analysis reports per-display stats, pairwise d′, and
held-out nearest-centroid accuracy for each feature set. Thresholds are in CONTRACT.md section 6.3.

Setup for this run: MacBook Air M4 plus two external displays (BenQ GW2490T, LG ULTRAGEAR), with the
Logitech C922 webcam. 2 rounds × 3 displays, 5 s hold per display (150 frames per display at 15 fps).

## Result

## M1 head-pose gate result

- Date: 2026-10-24 23:51
- Camera: C922 Pro Stream Webcam
- Displays: BenQ GW2490T (1920x1080 pt), Built-in Retina Display (1470x956 pt, built-in), LG ULTRAGEAR (2560x1440 pt)
- Overall verdict: **GO** (best feature set: Vision angles)
- Thresholds: GO needs d′ ≥ 3.0, accuracy ≥ 95.0%, face detection ≥ 90.0%; MARGINAL needs d′ ≥ 2.0, accuracy ≥ 85.0%, face detection ≥ 75.0%; at least 30 face samples per display; standard deviations floored at 0.5°.

### Vision angles — GO

| Display | Frames | Face % | Mean yaw | Mean pitch | Std yaw | Std pitch |
|---|---:|---:|---:|---:|---:|---:|
| BenQ GW2490T | 150 | 100.0 | 61.1 | 5.7 | 1.8 | 3.2 |
| Built-in Retina Display | 150 | 100.0 | 41.7 | 11.1 | 2.5 | 2.7 |
| LG ULTRAGEAR | 150 | 100.0 | 2.4 | 10.0 | 1.3 | 4.1 |

| Pair | Mean distance | d′ |
|---|---:|---:|
| BenQ GW2490T vs Built-in Retina Display | 20.1 | 8.3 |
| BenQ GW2490T vs LG ULTRAGEAR | 58.9 | 37.5 |
| Built-in Retina Display vs LG ULTRAGEAR | 39.3 | 19.7 |

Held-out accuracy: 100.0%

Notes:
- Weakest pair: BenQ GW2490T and Built-in Retina Display, d′ 8.3.

### Landmark angles — GO

| Display | Frames | Face % | Mean yaw | Mean pitch | Std yaw | Std pitch |
|---|---:|---:|---:|---:|---:|---:|
| BenQ GW2490T | 150 | 100.0 | 50.3 | 16.1 | 3.0 | 3.1 |
| Built-in Retina Display | 150 | 100.0 | 37.9 | 12.1 | 2.3 | 3.2 |
| LG ULTRAGEAR | 150 | 100.0 | 18.7 | -3.1 | 0.7 | 1.2 |

| Pair | Mean distance | d′ |
|---|---:|---:|
| BenQ GW2490T vs Built-in Retina Display | 13.0 | 5.4 |
| BenQ GW2490T vs LG ULTRAGEAR | 37.0 | 19.3 |
| Built-in Retina Display vs LG ULTRAGEAR | 24.5 | 14.6 |

Held-out accuracy: 98.9%

Notes:
- Weakest pair: BenQ GW2490T and Built-in Retina Display, d′ 5.4.
- Landmarks were unavailable in 0.0% of frames with a face.

## Decision

**GO.** Head pose separates every display pair on this setup by a wide margin. The weakest pair (BenQ vs
built-in) reaches d′ 8.3 against a threshold of 3.0, held-out accuracy is 100%, and the face is found in 100% of
frames, even at the BenQ's ~61° yaw. M2 (CalibrationModel + SwitchDecider) proceeds on this signal.

What this means for M2 and later:

1. **Primary features: Vision angles.** They separate better than the landmark proxy here (weakest d′ 8.3 vs
   5.4). Keep the landmark proxy as a secondary signal and fallback.
2. **Calibrate per camera.** The C922 sees the LG almost head-on (yaw ≈ 2°), so all profiles are relative to
   where the camera is mounted. This confirms PLAN.md's per-camera, per-layout calibration (M5).
3. **Yaw sign:** with this setup, Vision yaw increases as the head turns toward the displays on the left of
   the arrangement (LG ≈ 2°, built-in ≈ 42°, BenQ ≈ 61°). The landmark proxy moves the same way.
4. **Pitch is noisier than yaw** (std up to 4.1° vs 1.3–2.5°). The decider should rely mainly on yaw, use
   pitch as support, and use a per-display spread rather than a single global threshold.
5. **Three displays separate cleanly.** The MVP stays at 2 tracked displays per D3 (user decision), but since
   all logic is generic over N, raising `SwayPolicy.maxTrackedDisplays` to 3 looks viable on this setup.
   That is the user's call after M2.

What this gate did **not** measure (still open for M2, M5 and M7):

- Glances, head turns in motion, and natural, non-deliberate looks. M2's dwell and hysteresis tests cover these.
- Day-to-day posture and chair drift (PLAN.md risk 3), lighting changes, and long sessions.
- The built-in MacBook camera. Only the C922 was tested; rerun the gate if switching cameras.
- One session, one sitting.
