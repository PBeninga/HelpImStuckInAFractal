# Active shape implementation plan

> Execute inline using superpowers:executing-plans and test-driven-development.

**Goal:** Sequential active shapes, fog-covered swaps and human-prompted agent scripts.
**Spec:** ../specs/2026-10-12-active-shape-design.md
**Architecture:** ShapeRun owns transient progression and overrides. ShapeList owns saved objectives. FractalParams exposes a shared visible-shape selection and escape boundary to rendering, CPU sensing and navigation. Main wires the controller, view and agent tools.
**Tech stack:** Godot GDScript/shaders and Node voice server.

## Constraints

- Performance cost explicitly approved in this session; add no rays.
- Work in the current checkout; no push, merge, rebase or publishing.
- Headless verification only. No recursive force deletion.
- Keep authoring tables unchanged by scripted runtime edits.

## Review focus

- Delayed commands arriving after a stage/reset must be rejected.
- A nonzero spawn must agree across the renderer, CPU bounds and planner.
- Fog must fully cover the geometry switch even with cached/phosphor imagery.
- Old saved levels must load with sensible objectives and no inherited run state.
- Duplicate/unsolicited commands must not consume objectives or edit inactive shapes.

## Task 1: Authoring and progression

- [x] Add headless tests in tests/active_shape_test.gd for persistence, first-stage selection, required commands, human authorization, ordered transitions and reset.
- [x] Run `godot4 --headless --path . -s tests/active_shape_test.gd`; confirm failure before implementation.
- [x] Add src/gameplay/shape_run.gd and ShapeList stage settings. Add independent runtime selection/boundary helpers to FractalParams.
- [x] Verify the controller tests, including invalid inversion commands and nonzero spawn.

## Task 2: Game and geometry integration

- [x] Wire Main launch/load/spawn reset, per-frame runtime overrides and stage fog. Expose stage settings and active indicator in ShapeListPane.
- [x] Filter shader uploads and CPU scene functions through the runtime selection. Copy runtime boundary into planner/scan snapshots; use spawn-centered sphere intersections.
- [x] Add integration tests for renderer uploads, CPU selection, fog midpoint and final-only escape. Update old escape tests to explicitly use unscripted fixtures.
- [x] Run affected Godot suites and full headless suite; inspect failures rather than suppressing them.

## Task 3: Agent protocol

- [x] Add an apply_shape_command tool with expected run/stage/command and human-message authorization. Expose the briefing through direct status and ship status.
- [x] Send startup/reset/stage briefings and load the initial briefing into voice-session instructions. Update persona to prohibit unsolicited edits, including on tool/event completion.
- [x] Test tool dispatch, stale authorization, startup briefing and persona rules. Run call-center and Node server suites.
- [x] Request an independent code review, address substantive findings, verify and commit the complete implementation locally.

## Execution record

- Design: performance approval received; all other project workflow approval gates waived by project instructions and user.
- Implementation completed in the original checkout.
- Ruling: keep saved camera position on load; only Return to spawn moves the
  player. This preserves existing level loading while restarting stage progress.
- Ruling: legacy levels missing scripts acquire supported defaults; explicitly
  empty scripts remain unscripted. Invalid saved scripts remain blocked.
- Review: bound inversion and repeated-command stale retries reproduced RED,
  fixed, and verified GREEN. Commands now include command_index and human_turn.
- Review's deferred visual judgment: no GPU window launched; appearance remains
  unverified. No deferred code findings.
- Verification: 65 game suites passed (5,412 checks in the full run); the existing
  screen_depth_cache_test fails three checks because the unchanged cache creates
  a second raymarch pass, whereas its unchanged test expects one. HEAD contains
  the same duplicate-pass implementation and expectations.
- Verification: voice server 20/20 tests, MCP suite, and call-center console tools
  47/47 checks passed. New active-shape suites pass; additional agent save/load
  checks also passed after the full run.
- Existing call-center full-suite failures concern its obsolete demo/landmark
  tools, sample route geometry and boundary grep. These are outside this change;
  HEAD already lacks the fly_to_feature/DemoMission interfaces those tests use.
- No push, publish, worktree creation, GUI launch or recursive deletion.

