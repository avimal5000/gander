## What & why

Closes #

## Behavior checklist
- [ ] Cursor is never moved; only keyboard focus changes
- [ ] Uncertain input (ambiguous pose, face lost, camera busy, Focus Lock on) results in no switch
- [ ] Works with the current display layout; layout changes handled

## Privacy checklist
- [ ] No networking code (`scripts/privacy-guard.sh` passes)
- [ ] No frames or images written anywhere; only numeric pose traces, DEBUG builds only
- [ ] Camera runs only while needed (pause, sleep, lock, quit turn it off)
- [ ] No analytics, accounts, or crash reporters

## Verification
- [ ] `swift test` in `SwayCore` passes
- [ ] `xcodebuild` builds with zero warnings in our code
- [ ] `scripts/lint.sh` clean
- [ ] Manually checked on real hardware (describe):
