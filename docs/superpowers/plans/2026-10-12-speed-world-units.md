# Speed-based world units implementation plan

**Goal:** One gameplay world unit equals one second of travel at current player speed. Origin distance and authored advancement thresholds use this live unit.

**Spec:** User approved changing both readouts and progression, including the CPU cost of live speed evaluation. Preserve scene coordinates and rendering-only clipping. Use current flight speed including sprint, wheel factor and speed limiter.

**Architecture:** Main samples `fly.current_speed()` once per game frame, after resolving geometry. ShapeRun stores the scene-units-per-world-unit scale in FractalParams and uses it for normalized origin distance and advancement. F4 and planner consume the same scale. Camera changes no longer run progression before the frame's new speed is available.

**Constraints:** Work in the current checkout; headless verification only; no push, publish, merge, rebase or recursive force-delete. Existing unrelated changes and six failing baseline suites are outside this task.

## Steps

- [x] Add a regression to `tests/gameplay_menu_test.gd`: at scene distance 10 and speed 2, expect distance 5; at speed 4 expect 2.5; change wheel/sprint/limiter without moving and verify next-frame updates; threshold 3 must remain inside at speed 4 and advance at speed 2.
- [x] Run the test headlessly and observe incorrect values before implementation.
- [x] Add `world_unit_size` to FractalParams, copied by `copy_run_from`. Add ShapeRun conversion and a scale-change signal. Sample once in Main's progression check; remove immediate camera-triggered advancement. Use the conversion in F4 and the scene-radius conversion in the route planner.
- [x] Clarify authored threshold help and run briefing. Keep numeric saved thresholds unchanged; their unit is now the requested speed-based unit.
- [x] Give fixed-coordinate integration fixtures a fixed speed of 1 and explicitly advance their frame after teleports. Verify tiny movement, changed speed at rest, hidden F4 progression, reset and multi-level transitions.
- [x] Finish the full headless suite and report baseline failures separately. Commit this task’s changes separately from existing local work.

## Review focus

- Changing speed without moving must refresh F4 and progression on the next frame.
- Zero/invalid speed must never divide by zero.
- Nonzero spawn and tiny coordinates must preserve 64-bit precision.
- Rendering bounds must remain in scene coordinates.
- Route targets and agent briefing must identify the converted boundary consistently.

## Verification baseline

Before this change: 63/69 suites passed. Failures: console_test, fly_camera_test, menus_test, screen_depth_cache_test, ui_chat_test, ui_journey_test. Original tiny-distance display regression passes 41 checks after its formatting fix.

## Execution record

- Initial speed regression failed six checks before implementation; all 50 gameplay-menu checks now pass.
- Focused suites pass: active shape (59), active-shape integration (30), next-level distance (17), gameplay (33), active-shape agent (18), escape controls (20), per-shape look (49).
- Review found enlarged planner boundaries could exceed measured clearance. Regression failed with target 40.004 versus expected 15; planner now caps the leg and permits only its existing tiny boundary-crossing margin. All 7 planner checks pass.
- Review found live numeric briefing values could be stale before a stage’s first frame. Removed those new numeric fields; briefings describe the unit definition without reporting unsampled numbers.
- Two integration fixtures assumed synchronous advancement on a camera signal. Updated them to execute the frame’s progression step, matching the requested per-frame sampling.
- No new rendering rays; Main evaluates current speed once per game frame so progression remains current with F4 closed.

Final verification: `tests/run_all.sh` with Godot 4.6.1 headless passed 64/70 suites. The six failing suites are unchanged from baseline: console_test, fly_camera_test, menus_test, screen_depth_cache_test, ui_chat_test, ui_journey_test. All newly added and adjusted tests pass; `git diff --check` passes. Final review has no remaining findings. No windowed/GPU run was launched.
