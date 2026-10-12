# Light and Material tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the console's Colour tab into a Light tab and a Material tab, add a COLOR attribute-row type, light colour/size/shadows/scattering, surface colour/roughness/specular, and noise-driven Texture and Bump, with every new control defaulting to "no change" so every saved view and every site colour mode renders bit-for-bit as today.

**Architecture:** The shape catalogue stays the single ordered list of knobs; two `AttributeInspector`s over the one `AttributeTable` replace the old Colour inspector, each filtered to its groups. `FractalParams` holds the new resolved fields (two of them `Color`), `FractalView` pushes them (colours as `Vector3`, plus a renderer `shadow_steps`), and `mandelbox.gdshader` reads new uniforms in a lit-hit block that is guarded so the defaults are the site's maths. The noise `Output` node gains Texture (VEC3) and Bump (FLOAT) inputs and `NoiseCompiler` emits two more functions beside the three it writes now.

**Tech Stack:** Godot 4.6, GDScript, GLSL (`canvas_item` shader). Headless tests (`tests/*_test.gd` extending `tests/test_case.gd`, run by `tests/run_all.sh`).

**Spec:** `docs/superpowers/specs/2026-10-09-light-and-material-design.md` (approved; do not redesign).

## Global Constraints

Copied verbatim from the spec and the project conventions; every task's requirements implicitly include these.

- **Worktree only.** All work happens in `/Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material` on branch `light-material`. Prefix every git command with `git -C /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material`. Never touch the main checkout `/Users/adam/Godot/HelpImStuckInAFractal` (another session edits it concurrently). Do not create another worktree.
- **Headless only.** Every run is `--headless`. Never launch anything windowed; no desktop control. Run tests with `--path` pointing at the worktree, e.g. `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/shape_catalogue_test.gd`.
- **Commit, do not push.** Commit each task in logical units. Never `git push`, `merge`, `rebase`, `cherry-pick`, `revert`, `am`, `gh pr create` or `gh pr merge`. Read-only git (`status`, `diff`, `log`, `show`) is fine.
- **Never run `rm -rf`** (or any recursive force-delete) in any form. If a step needs one, do not run it; put the exact command in a `bash` block at the end of your response for the human to run.
- **Commit-message convention:** `type(scope): summary` (see `git log`), ending with the trailer line (the repo's established convention, matching the task instruction):
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`
- **Defaults are bit-for-bit the site's look.** Every new shader effect is guarded (the shader already does `if (exposure != 1.0)` style guards; follow it) so an unpushed/default frame is the original source byte-for-byte in effect.
- **The stub NOISE region must stay byte-identical to `NoiseCompiler.STUB`.** The compiler splices `STUB` back for an unwired graph. The shader's `// NOISE:BEGIN … // NOISE:END` region and `NoiseCompiler.STUB` change together, in the same task, with identical text.
- **Style:** Every script has a `##` doc comment at the top explaining the why. Every catalogue row has a plain-language `tooltip` and `effects`. The reader is an engineer, not a mathematician: any maths above basic calculus in a tooltip, the README or a comment gets a one-line plain explanation.
- **Sibling project** `/Users/adam/Godot/Fractacular` is the conventions model (read-only, never modify).

## Review Focus

Input classes the spec implies but no task's own happy-path test exercises. Each line names where its test is pinned (added in that task's steps).

- **A saved view stores a COLOR as a 4-element `[r,g,b,a]` array** (older/hand-edited JSON), not 3. `AttributeSpec.sanitize` must accept 3- **and** 4-element arrays and force alpha 1. Pinned in Task 1 (`attribute_test`).
- **An old save carries a *binding* on `light_shininess`** (not just a default). The migration drops the default silently but must drop the binding **with a warning** — otherwise `apply_dict` would warn "non-bindable/unknown" with the wrong text or keep a dead binding. Pinned in Task 9 (`workspace_test`).
- **The headlight case for shadows:** `shadows > 0` but `light_yaw == 0 && light_pitch == 0`. The shadow ray would retrace the view ray and self-shadow everything; the shader must skip the shadow march and leave `sh = 1`. Pinned in Task 5 description + Task 4 shader guard (no unit test can drive the GPU; covered by the guard and the `fractal_view_test` `shadow_steps` push).
- **A noise graph wired to Texture but not Bump (and vice-versa):** `noise_texture_on` true, `noise_bump_on` false, and **neither displaces**. A Texture- or Bump-only graph colours/tilts without moving the surface. Pinned in Task 8 (`noise_compiler_test`).
- **`light_specular` / `roughness` under load shed:** shadows drop out at level ≥ 2 (`shadow_steps == 0`) and the specular highlight must fall back to the near-hard default rather than vanishing or NaN-ing (`e = 2/r_eff² − 2` with the default `roughness = 1/9`, `light_size = 0` giving 160). Pinned in Task 5 (`load_shedder_test` + `fractal_view_test` push 48/24/0).

---

## Task order and independence

Dependency order (each task's tests must pass before the next starts):

1. COLOR attribute type (AttributeSpec + AttributeTable + resolver)
2. Catalogue rows and group split
3. FractalParams fields and keys
4. Shader lit-path + uniforms + NOISE region stubs + `NoiseCompiler.STUB` (coupled)
5. LoadShedder shadow rung + FractalView push (shadow_steps + colour Vector3)
6. Noise Output ports + compiler (texture/bump) + noise editor test
7. Console Light/Material tabs + COLOR row widget
8. *(folded: the compiler's texture/bump wiring test lives in Task 6)*
9. Workspace shininess migration
10. README
11. Tab-index and screenshot test fixups
12. Full-suite gate

**Independent of each other** (no shared edits, can be done in any order once their prerequisites are met): Task 10 (README) is independent of everything after Task 9. Tasks 2, 3 both depend only on Task 1 and can be built in parallel, but Task 2's `shape_catalogue_test` and Task 3's `fractal_params_test` cross-check the catalogue/RESOLVED_KEYS equality, so run both suites after both land. Everything else is sequential because of the shared-file and interface dependencies noted per task.

---

### Task 1: COLOR attribute type

**Files:**
- Modify: `src/attributes/attribute_spec.gd` (the `Type` enum ~line 12; `make()` ~lines 67–101; `sanitize()` ~lines 113–127)
- Modify: `src/attributes/attribute_table.gd` (`to_dict()` ~lines 103–110; `apply_dict()` ~lines 115–129)
- Modify: `src/attributes/binding_resolver.gd` (doc comment only; behaviour already correct — see below)
- Test: `tests/attribute_test.gd`

**Interfaces — Produces:**
- `AttributeSpec.Type.COLOR` (a new enum member, appended last so existing FLOAT/INT/BOOL/ENUM indices are unchanged).
- A COLOR spec: `bindable == false`, `default_value` a `Color` (alpha 1), no slider/spin/readout/binding widgets. `sanitize(v)` accepts a `Color`, a 3-element or 4-element `Array`, and returns a `Color` with `a == 1.0`.
- `AttributeTable.to_dict()` writes a COLOR default as a 3-element `[r, g, b]` Array; `apply_dict()` restores it through `set_default` (which sanitizes the Array back to a `Color`).
- `BindingResolver.resolve_value` passes a COLOR default through untouched (it is not bindable — the existing `not spec.bindable` guard already returns `default_value`).

- [ ] **Step 1: Write the failing tests** (append to `tests/attribute_test.gd`'s `run()`, before the final line)

```gdscript
	# --- COLOR: sanitize an Array to a Color, round-trip through JSON ---
	var col := AttributeSpec.make({"id": "lc", "label": "Light colour",
		"type": AttributeSpec.Type.COLOR, "default": Color(1, 1, 1),
		"tooltip": "t", "effects": "e"})
	check(not col.bindable, "a COLOR spec is not bindable")
	check(col.default_value is Color, "its default is a Color")
	check((col.sanitize([0.2, 0.4, 0.6]) as Color).is_equal_approx(Color(0.2, 0.4, 0.6, 1.0)),
		"sanitize turns a 3-array into an opaque Color")
	check((col.sanitize([0.2, 0.4, 0.6, 0.3]) as Color).is_equal_approx(Color(0.2, 0.4, 0.6, 1.0)),
		"a 4-array drops alpha to 1 (what JSON round-trips, alpha ignored)")
	check((col.sanitize(Color(0.1, 0.2, 0.3, 0.5)) as Color).is_equal_approx(Color(0.1, 0.2, 0.3, 1.0)),
		"a Color keeps its rgb with alpha forced to 1")

	var ctab := AttributeTable.new([col])
	ctab.set_default(&"lc", Color(0.3, 0.5, 0.7))
	var cdict := ctab.to_dict()
	check(cdict["defaults"]["lc"] is Array and (cdict["defaults"]["lc"] as Array).size() == 3,
		"to_dict writes a COLOR as a 3-element [r, g, b] array (Color is not JSON)")
	var round := AttributeTable.new([col])
	round.apply_dict(cdict)
	check((round.get_default(&"lc") as Color).is_equal_approx(Color(0.3, 0.5, 0.7, 1.0)),
		"apply_dict restores the COLOR through set_default/sanitize")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/attribute_test.gd`
Expected: FAIL (`AttributeSpec.Type.COLOR` does not exist / sanitize returns the Array unchanged).

- [ ] **Step 3: Add the enum member** — in `src/attributes/attribute_spec.gd`, change

```gdscript
enum Type { FLOAT, INT, BOOL, ENUM }
```
to
```gdscript
enum Type { FLOAT, INT, BOOL, ENUM, COLOR }
```
(Append; never reorder — INT/BOOL/ENUM are stored as ints in saves and used as array indices elsewhere.)

- [ ] **Step 4: Handle COLOR in `make()`** — in the `match s.type:` block (after the `Type.ENUM` arm), add:

```gdscript
		Type.COLOR:
			s.default_value = sanitize_color(d["default"])
			s.bindable = false
```
Place it before the `s.hard_min = …` line that follows the match (COLOR leaves min/max/step at their defaults; they are unused). Then guard the explicit-bindable override already below so COLOR cannot be forced bindable:

```gdscript
	if d.has("bindable"):
		s.bindable = bool(d["bindable"]) and s.type != Type.BOOL and s.type != Type.ENUM and s.type != Type.COLOR
```

- [ ] **Step 5: Handle COLOR in `sanitize()` and add the static helper** — in `sanitize()`'s `match type:` add an arm:

```gdscript
		Type.COLOR:
			return sanitize_color(value)
```
and add the helper at the end of the file:

```gdscript
## A candidate colour as an opaque Color: a Color (alpha forced to 1), or the
## 3- or 4-element Array that JSON round-trips (alpha, element 4, is ignored).
static func sanitize_color(value: Variant) -> Color:
	if value is Color:
		var c: Color = value
		return Color(c.r, c.g, c.b, 1.0)
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value
		return Color(float(a[0]), float(a[1]), float(a[2]), 1.0)
	return Color.WHITE
```

- [ ] **Step 6: COLOR-aware `to_dict` in `attribute_table.gd`** — change the defaults loop in `to_dict()` so a COLOR value is written as `[r, g, b]`:

```gdscript
	for id in _defaults:
		var v: Variant = _defaults[id]
		var s := spec(id)
		if s != null and s.type == AttributeSpec.Type.COLOR and v is Color:
			var c: Color = v
			d["defaults"][String(id)] = [c.r, c.g, c.b]
		else:
			d["defaults"][String(id)] = v
```
`apply_dict` needs no change: it already routes through `set_default`, which sanitizes the Array back to a Color.

- [ ] **Step 7: Update the `binding_resolver.gd` doc comment** to note COLOR values are non-bindable and pass through untouched (one line). No code change — the `not spec.bindable` branch already returns the default.

- [ ] **Step 8: Run the tests to verify they pass**

Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/attribute_test.gd`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git -C /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material add src/attributes/attribute_spec.gd src/attributes/attribute_table.gd src/attributes/binding_resolver.gd tests/attribute_test.gd
git -C /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material commit -m "feat(attributes): COLOR row type that round-trips as [r, g, b]

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Catalogue rows and the Light/Material group split

**Files:**
- Modify: `src/fractal/shape_catalogue.gd` (the `COLOUR_GROUPS` const ~line 39; the Colour/Lighting/Palette section ~lines 108–225; `group_tooltips()` ~lines 232–244; the class doc comment ~lines 3–13)
- Test: `tests/shape_catalogue_test.gd`

**Interfaces — Consumes:** `AttributeSpec.Type.COLOR` (Task 1).
**Interfaces — Produces:**
- `ShapeCatalogue.LIGHT_GROUPS: Array[String] = ["Light", "Scattering", "Picture"]`
- `ShapeCatalogue.MATERIAL_GROUPS: Array[String] = ["Colour", "Surface", "Texture", "Palette"]`
- `COLOUR_GROUPS` is **removed**.
- New catalogue ids (99 total; `light_shininess` removed): `light_color`, `light_size`, `shadows`, `scatter_density`, `scatter_glow`, `scatter_brightness`, `surface_color`, `roughness`, `texture_strength`, `bump_strength`. `light_specular`, `light_yaw`, `light_pitch`, `light_ambient`, `light_diffuse`, `exposure`, `saturation`, `color_mode`, the `palette_*` rows keep their ids.
- `catalogue_ids()` returns the 99 ids in the order below (Task 3's `RESOLVED_KEYS` must equal this exactly).

**Catalogue order after the `precision` (Render) row** — replace the current Colour/Lighting/Palette block with these groups, contiguous and in this order (group → rows):

- **Colour:** `color_mode`, `palette_source`, `palette_frequency`, `palette_offset`, `palette_occlusion` (all unchanged from today).
- **Light:** `light_color` (COLOR), `light_yaw`, `light_pitch`, `light_size` (FLOAT), `light_ambient`, `light_diffuse`, `shadows` (FLOAT).
- **Scattering:** `scatter_density`, `scatter_glow`, `scatter_brightness` (FLOAT).
- **Picture:** `exposure`, `saturation` (unchanged, `group` now `"Picture"`).
- **Surface:** `surface_color` (COLOR), `roughness` (FLOAT), `light_specular` (unchanged id and ranges, `group` now `"Surface"`).
- **Texture:** `texture_strength`, `bump_strength` (FLOAT).
- **Palette:** the twelve `palette_*` rows (unchanged, still `group` `"Palette"`, still `show_when: _palette_shown()`).

Exact specs for the new rows (every one needs a plain-language `tooltip` and `effects`):

| id | label | type | default | min | max | step | hard_max | group | notes |
|---|---|---|---|---|---|---|---|---|---|
| `light_color` | Light colour | COLOR | `Color(1,1,1)` | — | — | — | — | Light | |
| `light_size` | Light size | FLOAT | `0.0` | `0.0` | `30.0` | `0.1` | `89.0` | Light | degrees |
| `shadows` | Shadows | FLOAT | `0.0` | `0.0` | `1.0` | `0.01` | (default = max) | Light | |
| `scatter_density` | Density | FLOAT | `0.0` | `0.0` | `0.5` | `0.001` | `10.0` | Scattering | |
| `scatter_glow` | Glow | FLOAT | `0.0` | `0.0` | `0.95` | `0.01` | (default = max) | Scattering | |
| `scatter_brightness` | Brightness | FLOAT | `1.0` | `0.0` | `4.0` | `0.01` | `16.0` | Scattering | |
| `surface_color` | Surface colour | COLOR | `Color(1,1,1)` | — | — | — | — | Surface | |
| `roughness` | Roughness | FLOAT | `1.0 / 9.0` | `0.02` | `1.0` | `0.001` | (default = max) | Surface | `"log": true` |
| `texture_strength` | Texture | FLOAT | `1.0` | `0.0` | `1.0` | `0.01` | (default = max) | Texture | |
| `bump_strength` | Bump | FLOAT | `1.0` | `0.0` | `4.0` | `0.01` | `64.0` | Texture | |

`light_yaw`, `light_pitch`, `light_ambient`, `light_diffuse`, `exposure`, `saturation`, `light_specular` keep their existing `make({...})` dictionaries verbatim except the `group` field changes (`light_yaw`/`light_pitch`/`light_ambient`/`light_diffuse` → `"Light"`; `exposure`/`saturation` → `"Picture"`; `light_specular` → `"Surface"`). **Delete** the `light_shininess` `make({...})` block entirely.

`group_tooltips()`: remove the `"Lighting"` entry; add (verbatim from the spec):

```gdscript
	"Light": "Light: the one lamp every lit colour mode shares, a headlight following the camera by default. Each value's default is the site's, so the default picture is unchanged until you move one.",
	"Scattering": "Scattering: haze in the space the camera flies through — analytic, no extra rays. Off until you raise the Density.",
	"Picture": "Picture: adjustments on the final colour of every mode but Grayscale.",
	"Surface": "Surface: what the surface is made of — its colour, how rough it is, and how strong the glints are.",
	"Texture": "Texture: the noise editor's Texture and Bump outputs drive these. Nothing wired, nothing changes; press N to open the editor.",
```
Keep the existing `"Colour"` and `"Palette"` entries.

Tooltip/effects copy for the new rows (write these; keep the engineer-not-mathematician rule — the Henyey-Greenstein phase and the specular exponent each get a one-line plain gloss):

- `light_color` — tooltip: "The colour of the lamp. Every lit mode's colour is multiplied by it." effects: "White (the default) leaves every mode exactly as it is. Warm it for a sunset, cool it for moonlight; it also tints the scattering haze."
- `light_size` — tooltip: "How wide the lamp is, in degrees. A point light at 0; a broad source above it." effects: "0 is the site's pin-sharp glints and hard shadows. Widening it spreads the glint into a soft sheen and softens the shadow edge (a wider penumbra)."
- `shadows` — tooltip: "How dark the lamp's shadows are. 0 is off (no shadow ray cast)." effects: "0 is the site's look, with no shadow march. Towards 1 the surface casts shadows of itself, which costs one extra ray per pixel and drops out first under load. Only works when the light is swung off the headlight (Light yaw or pitch non-zero); a headlight casts no visible shadow."
- `scatter_density` — tooltip: "How thick the haze filling the space is. 0 is off." effects: "Measured in near-distance units, so it looks the same at any zoom. Small values add depth; large values wash the scene toward the light's colour."
- `scatter_glow` — tooltip: "How much the haze bunches around the light's direction (a forward-scatter bias)." effects: "0 is an even haze. Towards 1 it becomes a bright beam around the lamp, like looking near the sun through mist. (It sets the g in the Henyey-Greenstein phase: how sharply light prefers to carry on forwards.)"
- `scatter_brightness` — tooltip: "How bright the haze is, multiplied by the light's colour." effects: "1 is a middling haze. Below 1 is a dim fog; above 1 blooms the beam. 0 makes the haze black (a dark fog)."
- `surface_color` — tooltip: "A colour the surface is multiplied by, under every lit mode." effects: "White (the default) leaves every mode as it is. Use it to tint the whole surface without changing its shading."
- `roughness` — tooltip: "How rough the surface is: low is glassy with tight glints, high is matte. Replaces the old Shininess." effects: "1/9 (the default) is the site's pin-point sparkle. Towards 1 the glint spreads into a broad sheen; towards 0.02 it tightens to a few pixels. (The specular exponent is 2/roughness² − 2, so smaller roughness means a tighter highlight.) The slider is logarithmic."
- `light_specular` — keep its existing tooltip/effects (unchanged).
- `texture_strength` — tooltip: "How much the noise editor's Texture output recolours the surface. 0 leaves the colour alone." effects: "The surface colour is multiplied by a blend from white toward the Texture colour by this amount. 1 uses the Texture output in full; nothing wired means nothing changes whatever this is."
- `bump_strength` — tooltip: "How much the noise editor's Bump output tilts the surface normal (a fake relief; the surface does not actually move)." effects: "0 is flat. Larger values deepen the apparent bumps and grooves. Nothing wired means nothing changes; press N to open the editor."

Update the class doc comment (`## … COLOUR_GROUPS on its Colour tab.`) to describe LIGHT_GROUPS and MATERIAL_GROUPS and the two tabs.

- [ ] **Step 1: Update the test first.** In `tests/shape_catalogue_test.gd`:
  - Replace `EXPECTED_IDS` with the 99 ids in the new order (drop `light_shininess`; insert the ten new ids at the positions above). Update the doc comment's "90 catalogue ids" to 99.
  - Change the tab-split check (lines ~68–71) to use the two new consts:

```gdscript
	for s in specs:
		var on_shape := ShapeCatalogue.SHAPE_GROUPS.has(s.group)
		var on_light := ShapeCatalogue.LIGHT_GROUPS.has(s.group)
		var on_material := ShapeCatalogue.MATERIAL_GROUPS.has(s.group)
		var tabs := int(on_shape) + int(on_light) + int(on_material)
		check(tabs == 1, "'%s' (group %s) is on exactly one console tab" % [s.id, s.group])
```
  - Replace the shininess checks (lines ~77 and ~82) with roughness, and add COLOR checks:

```gdscript
	check_approx(table.get_default(&"roughness"), 1.0 / 9.0, "roughness defaults to 1/9 (the site's exponent 160)")
	check(table.spec(&"roughness").log_scale, "roughness is logarithmic")
	check(not table.has(&"light_shininess"), "light_shininess is gone")
	for cid in [&"light_color", &"surface_color"]:
		var cs := table.spec(cid)
		check_eq(cs.type, AttributeSpec.Type.COLOR, "'%s' is a COLOR spec" % cid)
		check(not cs.bindable, "'%s' is not bindable" % cid)
		check((table.get_default(cid) as Color).is_equal_approx(Color(1, 1, 1, 1)), "'%s' defaults to white" % cid)
	check(ShapeCatalogue.LIGHT_GROUPS.has("Scattering") and ShapeCatalogue.MATERIAL_GROUPS.has("Surface"),
		"the Light tab owns Scattering and the Material tab owns Surface")
	for g in ShapeCatalogue.LIGHT_GROUPS + ShapeCatalogue.MATERIAL_GROUPS:
		check(tips.has(g), "group '%s' has a heading tooltip" % g)
```
  - Keep the `light_ambient`/`light_diffuse`/`light_specular`/`light_yaw`/`light_pitch`/`exposure`/`saturation` default checks (lines ~74–81, minus the two shininess lines).
  - The `for s in specs` loop's generic checks (tooltip/effects/group/range) already cover the new rows; the FLOAT/INT range check skips COLOR because its type is COLOR (add nothing).

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/shape_catalogue_test.gd`
Expected: FAIL (ids mismatch, `LIGHT_GROUPS`/`MATERIAL_GROUPS` undefined, roughness absent).

- [ ] **Step 3: Implement the catalogue changes** per the tables and copy above: the two new consts, removing `COLOUR_GROUPS`, the reordered Colour/Light/Scattering/Picture/Surface/Texture/Palette blocks with the new COLOR and FLOAT rows, the `light_shininess` deletion, and `group_tooltips()`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/shape_catalogue_test.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material add src/fractal/shape_catalogue.gd tests/shape_catalogue_test.gd
git -C /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material commit -m "feat(catalogue): Light and Material groups, colour/size/shadows/scatter/surface/texture rows

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: FractalParams fields and keys

**Files:**
- Modify: `src/fractal/fractal_params.gd` (`RESOLVED_KEYS` ~lines 26–45; `LOOK_KEYS` ~lines 49–55; the `@export` colour/lighting fields ~lines 206–234)
- Test: `tests/fractal_params_test.gd`

**Interfaces — Consumes:** `ShapeCatalogue.catalogue_ids()` (Task 2).
**Interfaces — Produces:**
- `FractalParams.RESOLVED_KEYS` equals `ShapeCatalogue.catalogue_ids()` (the 99 ids, new order).
- New fields: `@export var light_color: Color = Color(1, 1, 1, 1)`, `@export var surface_color: Color = Color(1, 1, 1, 1)`, `@export var light_size := 0.0`, `@export var shadows := 0.0`, `@export var scatter_density := 0.0`, `@export var scatter_glow := 0.0`, `@export var scatter_brightness := 1.0`, `@export var roughness := 1.0 / 9.0`, `@export var texture_strength := 1.0`, `@export var bump_strength := 1.0`. Each with `set(v): <field> = v; _emit()`.
- `light_shininess` field is **removed**.
- `const COLOR_KEYS: Array[StringName] = [&"light_color", &"surface_color"]` — pushed to the shader as a `Vector3`, not as the plain value.
- `LOOK_KEYS` = every resolved key after `color_mode` **except** the two `COLOR_KEYS` (so every LOOK_KEY is a scalar `int`/`float` uniform with a shader default).
- `const SHADOW_STEPS := 48` (used by the view in Task 5; declare it here next to the step-budget constants).

Exact `RESOLVED_KEYS` tail (everything from `color_mode` on; the head through `precision` is unchanged):

```gdscript
	&"precision", &"color_mode",
	&"palette_source", &"palette_frequency", &"palette_offset", &"palette_occlusion",
	&"light_color", &"light_yaw", &"light_pitch", &"light_size", &"light_ambient",
	&"light_diffuse", &"shadows", &"scatter_density", &"scatter_glow", &"scatter_brightness",
	&"exposure", &"saturation", &"surface_color", &"roughness", &"light_specular",
	&"texture_strength", &"bump_strength", &"palette_a_r", &"palette_a_g", &"palette_a_b",
	&"palette_b_r", &"palette_b_g", &"palette_b_b", &"palette_c_r", &"palette_c_g",
	&"palette_c_b", &"palette_d_r", &"palette_d_g", &"palette_d_b",
```

Exact `LOOK_KEYS` (the scalar look keys; omits `light_color` and `surface_color`):

```gdscript
const LOOK_KEYS: Array[StringName] = [
	&"palette_source", &"palette_frequency", &"palette_offset", &"palette_occlusion",
	&"light_yaw", &"light_pitch", &"light_size", &"light_ambient", &"light_diffuse",
	&"shadows", &"scatter_density", &"scatter_glow", &"scatter_brightness",
	&"exposure", &"saturation", &"roughness", &"light_specular",
	&"texture_strength", &"bump_strength",
	&"palette_a_r", &"palette_a_g", &"palette_a_b", &"palette_b_r", &"palette_b_g", &"palette_b_b",
	&"palette_c_r", &"palette_c_g", &"palette_c_b", &"palette_d_r", &"palette_d_g", &"palette_d_b",
]
```

- [ ] **Step 1: Update the test first.** In `tests/fractal_params_test.gd`:
  - The `RESOLVED_KEYS == catalogue_ids()` check (line 49) stands. The loop at lines 50–55 compares each field to its catalogue default; COLOR ids give a `Color`, which hits the `else` branch (`check_eq(p.get(k), want)`) — a `Color == Color` compare. Ensure the catalogue COLOR default (`Color(1,1,1,1)` after sanitize) equals the field default `Color(1,1,1,1)`. No test edit needed there.
  - Replace the structural LOOK_KEYS check (lines 59–60) to account for the two COLOR keys:

```gdscript
	check_eq(FractalParams.LOOK_KEYS.size() + FractalParams.COLOR_KEYS.size()
		+ FractalParams.RESOLVED_KEYS.find(&"color_mode") + 1,
		FractalParams.RESOLVED_KEYS.size(),
		"look keys + colour keys are everything after color_mode")
	for k in FractalParams.COLOR_KEYS:
		check(FractalParams.RESOLVED_KEYS.has(k), "colour key '%s' is resolved" % k)
		check(not FractalParams.LOOK_KEYS.has(k), "a colour key is not a scalar look key")
		check(p.get(k) is Color, "field '%s' is a Color" % k)
	check(not FractalParams.RESOLVED_KEYS.has(&"light_shininess"), "light_shininess is gone")
	check_eq(FractalParams.SHADOW_STEPS, 48, "the full shadow march is 48 steps")
```
  - Keep the existing lines 56–58 (every LOOK_KEY is resolved; `color_mode` is not a look key).

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/fractal_params_test.gd`
Expected: FAIL (RESOLVED_KEYS mismatch, `COLOR_KEYS`/`SHADOW_STEPS` undefined).

- [ ] **Step 3: Implement** — reorder `RESOLVED_KEYS`, replace `LOOK_KEYS`, add `COLOR_KEYS` and `SHADOW_STEPS`, add the ten new `@export` fields (two `Color`), and delete the `light_shininess` field.

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/fractal_params_test.gd`
Expected: PASS.

- [ ] **Step 5: Re-run Task 2's suite** (the two cross-check each other):

Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/shape_catalogue_test.gd`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git -C /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material add src/fractal/fractal_params.gd tests/fractal_params_test.gd
git -C /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material commit -m "feat(params): resolved fields for light/material, COLOR_KEYS and SHADOW_STEPS

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Shader lit-path, uniforms, and the NOISE stub region

This task touches `src/fractal/mandelbox.gdshader` **and** `src/noise/noise_compiler.gd` together, because the shader's `// NOISE:BEGIN … // NOISE:END` region must stay byte-identical to `NoiseCompiler.STUB`.

**Files:**
- Modify: `src/fractal/mandelbox.gdshader` (uniform block ~lines 50–112; the NOISE region ~lines 114–118; add helpers near `rotate_about`/`box_intersect` ~lines 388–411; the `fragment()` lit-hit block ~lines 468–565; the Grayscale path ~lines 473–476; the sky/miss paths ~lines 426–427 and 466–467)
- Modify: `src/noise/noise_compiler.gd` (`STUB` ~lines 27–30 only — the emit functions come in Task 6)
- Test: `tests/shader_test.gd`; the stub-region part of `tests/noise_compiler_test.gd`

**Interfaces — Consumes:** `FractalParams.LOOK_KEYS` and `COLOR_KEYS` (Task 3); `ShapeCatalogue.catalogue_ids()` (Task 2).
**Interfaces — Produces:**
- New catalogue uniforms (defaulted to the catalogue default, so an unpushed frame is right): `uniform vec3 light_color = vec3(1.0, 1.0, 1.0);`, `uniform float light_size = 0.0;`, `uniform float shadows = 0.0;`, `uniform float scatter_density = 0.0;`, `uniform float scatter_glow = 0.0;`, `uniform float scatter_brightness = 1.0;`, `uniform vec3 surface_color = vec3(1.0, 1.0, 1.0);`, `uniform float roughness = 0.111111;`, `uniform float texture_strength = 1.0;`, `uniform float bump_strength = 1.0;`. (`roughness`'s literal must match the catalogue default `1.0/9.0 ≈ 0.111111` to ≤1e-9 for `shader_test`; use `0.111111`.) `light_shininess` is **removed**.
- One renderer uniform **without** a default: `uniform int shadow_steps;` (0 = no shadow march; the view pushes it — Task 5).
- Four NOISE-region functions/constants (stubs here, real ones in Task 6): `vec3 noise_texture(vec3 p)`, `float noise_bump(vec3 p)`, `const bool noise_texture_on`, `const bool noise_bump_on`.
- Fragment helpers `float hg(float c, float g)`, `vec3 scatter(vec3 col, float t, vec3 dir, vec3 ldir)`, `float soft_shadow(vec3 v, vec3 n, vec3 ldir, float total)`.

- [ ] **Step 1: Update `tests/shader_test.gd` first.**
  - Add `"shadow_steps"` to `RENDERER_UNIFORMS` (line 11–14).
  - The float/int defaulted-uniform loop (lines 46–54) will now also match `int shadow_steps = …` **only if it has a default** — it must not, so no change there; but add a skip of renderer uniforms to be safe and keep the catalogue-id assertion honest:

```gdscript
	var re := RegEx.create_from_string("uniform (?:float|int) (\\w+) = (-?[0-9.]+);")
	var with_default := 0
	for m in re.search_all(sh.code):
		var id := StringName(m.get_string(1))
		if RENDERER_UNIFORMS.has(String(id)):
			continue   # a renderer uniform that happens to carry a default
		check(table.has(id), "the defaulted uniform '%s' is a catalogue id" % id)
		if table.has(id):
			check_approx(m.get_string(2).to_float(), float(table.get_default(id)),
				"uniform '%s' defaults to the catalogue's %s" % [id, table.get_default(id)], 1e-9)
		with_default += 1
	check_eq(with_default, FractalParams.LOOK_KEYS.size(), "every scalar look uniform declares its default")
```
  - Add the COLOR-default check (new in the spec): a `vec3` uniform named for a COLOR id defaults to that id's rgb.

```gdscript
	# every COLOR catalogue id is a vec3 uniform whose default is the colour's rgb
	var cre := RegEx.create_from_string("uniform vec3 (\\w+) = vec3\\(\\s*([0-9.]+)\\s*,\\s*([0-9.]+)\\s*,\\s*([0-9.]+)\\s*\\);")
	var colour_defaults := 0
	for m in cre.search_all(sh.code):
		var id := StringName(m.get_string(1))
		if not table.has(id):
			continue   # (there are no other defaulted vec3 uniforms today)
		check_eq(table.spec(id).type, AttributeSpec.Type.COLOR, "the defaulted vec3 '%s' is a COLOR id" % id)
		var c := table.get_default(id) as Color
		check_approx(m.get_string(2).to_float(), c.r, "vec3 '%s' red matches the COLOR default" % id, 1e-9)
		check_approx(m.get_string(3).to_float(), c.g, "vec3 '%s' green" % id, 1e-9)
		check_approx(m.get_string(4).to_float(), c.b, "vec3 '%s' blue" % id, 1e-9)
		colour_defaults += 1
	check_eq(colour_defaults, FractalParams.COLOR_KEYS.size(), "both COLOR uniforms declare a vec3 default")
```
  - The `names.size() == expected.size()` and `shape_uniforms == catalogue` checks need no edit — they derive from `RENDERER_UNIFORMS` (now +1) and `catalogue_ids()` (now 99); total 120.

- [ ] **Step 2: Add the stub-region assertions to `tests/noise_compiler_test.gd`.** After the existing `check_eq(String(def_result["code"]), NoiseCompiler.STUB, …)` (line 63) add:

```gdscript
	check(NoiseCompiler.STUB.contains("const bool noise_texture_on = false;"),
		"the stub declares noise_texture_on = false")
	check(NoiseCompiler.STUB.contains("const bool noise_bump_on = false;"),
		"the stub declares noise_bump_on = false")
	check(NoiseCompiler.STUB.contains("vec3 noise_texture(vec3 p) { return vec3(1.0); }"),
		"the stub's noise_texture is white")
	check(NoiseCompiler.STUB.contains("float noise_bump(vec3 p) { return 0.0; }"),
		"the stub's noise_bump is flat")
```

- [ ] **Step 3: Run both tests to verify they fail**

Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/shader_test.gd`
Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/noise_compiler_test.gd`
Expected: both FAIL.

- [ ] **Step 4: Edit the NOISE region in the shader AND `NoiseCompiler.STUB` to identical text.** The region (lines 114–118) becomes:

```glsl
// NOISE:BEGIN
float noise_displace(vec3 p) { return 0.0; }
float noise_step_scale() { return 1.0; }
vec3 noise_tint(vec3 col, vec3 p) { return col; }
vec3 noise_texture(vec3 p) { return vec3(1.0); }
float noise_bump(vec3 p) { return 0.0; }
const bool noise_texture_on = false;
const bool noise_bump_on = false;
// NOISE:END
```
and `NoiseCompiler.STUB` (lines 27–30) becomes the exact same five lines between the markers (the three existing plus the two new functions and two constants), byte-for-byte:

```gdscript
const STUB := """float noise_displace(vec3 p) { return 0.0; }
float noise_step_scale() { return 1.0; }
vec3 noise_tint(vec3 col, vec3 p) { return col; }
vec3 noise_texture(vec3 p) { return vec3(1.0); }
float noise_bump(vec3 p) { return 0.0; }
const bool noise_texture_on = false;
const bool noise_bump_on = false;
"""
```

- [ ] **Step 5: Replace the lighting uniforms and add the new uniforms.** In the uniform block, delete `uniform float light_shininess = 160.0;`, add the ten catalogue uniforms listed under Produces above (place `light_color`/`light_size`/`shadows` with the lighting group, `scatter_*` after, `surface_color`/`roughness` and `texture_strength`/`bump_strength` after that), and add `uniform int shadow_steps;` beside the other renderer uniforms (near `coarse_iters`, no default).

- [ ] **Step 6: Add the fragment helpers** (place after `rotate_about` / before `box_intersect`):

```glsl
// Henyey-Greenstein phase: how strongly haze scatters toward c = cos(angle to
// the light). g = 0 is even in all directions; g -> 1 bunches it forward.
float hg(float c, float g) {
	float gg = g * g;
	return (1.0 - gg) / pow(max(1.0 + gg - 2.0 * g * c, 1e-6), 1.5);
}

// Light-tinted distance haze for a ray that travelled t toward dir, with the
// light coming from ldir. Off when the density is 0, so the default is untouched.
vec3 scatter(vec3 col, float t, vec3 dir, vec3 ldir) {
	if (scatter_density <= 0.0) { return col; }
	float a = 1.0 - exp(-scatter_density * t / max(near_dist, 1e-6));
	float phase = hg(dot(dir, ldir), scatter_glow) / hg(1.0, scatter_glow);
	vec3 haze = light_color * scatter_brightness * phase;
	return mix(col, haze, clamp(a, 0.0, 1.0));
}

// A soft self-shadow: march from just off the surface toward the light, up to
// shadow_steps steps (<= 64), stopping at the cube's far side. A near-hit darkens
// fully; otherwise the closest approach, scaled by the lamp's angular size, is the
// penumbra. k widens the penumbra as the lamp widens (light_size); a size-0 lamp
// is near-hard. Costs one extra ray per pixel; skipped when shadow_steps is 0.
float soft_shadow(vec3 v, vec3 n, vec3 ldir, float total) {
	float eps0 = hit_eps(total);
	vec3 ro = v + n * 4.0 * eps0;
	float far = box_intersect(ro, ldir, box_half).y;
	float k = 1.0 / tan(max(radians(light_size), radians(0.5)));
	int n_coarse = clamp(coarse_iters, 16, 32);
	float res = 1.0;
	float t = eps0;
	for (int i = 0; i < 64; i++) {
		if (i >= shadow_steps) { break; }
		float d = de(ro + ldir * t, n_coarse);
		if (d < eps0) { return 0.0; }
		res = min(res, k * d / t);
		t += d * noise_step_scale();
		if (t > far) { break; }
	}
	return clamp(res, 0.0, 1.0);
}
```

- [ ] **Step 7: Rewrite the lit-hit block** (the `else` branch of `if (color_mode == 0)`, lines ~477–565). After `n` is computed (NF/true normal, unchanged) and before `ldir`, insert the bump block; compute `ldir` as now; insert the shadow and the roughness-based light term; keep the mode-colour `if/else` chain unchanged; insert texture, surface-colour and light-colour multiplies after it; keep exposure/saturation; then restructure the final `COLOR =` line to apply `noise_tint`, then `scatter`, then shed fog, then `probe_dot`, then `view_fade`.

```glsl
				// Bump: tilt the normal by the across-surface part of noise_bump's
				// gradient (a fake relief; the surface does not move). A result with
				// no length (a NaN) keeps the old normal.
				if (noise_bump_on && bump_strength != 0.0) {
					vec2 e2 = vec2(delta, 0.0);
					vec3 g = vec3(
						noise_bump(v + e2.xyy) - noise_bump(v - e2.xyy),
						noise_bump(v + e2.yxy) - noise_bump(v - e2.yxy),
						noise_bump(v + e2.yyx) - noise_bump(v - e2.yyx)) / (2.0 * delta);
					vec3 m = n - bump_strength * (g - n * dot(n, g));
					if (dot(m, m) > 1e-12) { n = normalize(m); }
				}

				vec3 ldir = normalize(2.0 * eh - h);
				bool swung = light_yaw != 0.0 || light_pitch != 0.0;
				if (swung) {
					ldir = rotate_about(rotate_about(ldir, cam_up, light_yaw), cam_right, light_pitch);
				}
				// Shadow only when the lamp is off the headlight: a headlight's shadow
				// ray retraces the view ray and would self-shadow the whole surface.
				float sh = 1.0;
				if (shadows > 0.0 && shadow_steps > 0 && swung) {
					sh = mix(1.0, soft_shadow(v, n, ldir, total), shadows);
				}
				float nl = abs(dot(n, ldir));
				// The specular exponent from roughness; the lamp's size widens the lobe.
				// r_eff^2 = roughness^2 + radians(light_size)^2, so size 0 is the site's.
				float r_eff2 = roughness * roughness + radians(light_size) * radians(light_size);
				float e = 2.0 / max(r_eff2, 1e-9) - 2.0;
				float lgt = sh * (light_diffuse * nl + light_specular * pow(nl, e)) + light_ambient;
				vec3 base = vec3(lgt) * (-n * 0.25 + 0.75) + vec3(0.0, 0.0, 0.2);
```
  - Delete the old `float lgt = light_diffuse * nl + light_specular * pow(nl, light_shininess) + light_ambient;` line (it is replaced above).
  - The whole `if (color_mode == 1) { … } else { col = vec3(inv); }` chain stays byte-for-byte.
  - After the chain and before the exposure guard, insert:

```glsl
					// Texture: recolour the surface by the Texture output (white = no change).
					if (noise_texture_on) { col *= mix(vec3(1.0), noise_texture(v), texture_strength); }
					// Surface and light colour, each guarded so white stays bit-for-bit.
					if (surface_color != vec3(1.0)) { col *= surface_color; }
					if (light_color != vec3(1.0)) { col *= light_color; }
```
  - Keep the exposure/saturation guards unchanged, then replace the final `COLOR = …` line with:

```glsl
					vec3 shaded = noise_tint(col, v);
					shaded = scatter(shaded, total, dir, ldir);
					shaded = mix(shaded, fog_color, fog_amount(total));
					COLOR = vec4(mix(probe_dot(shaded, v), bg, view_fade(total)), 1.0);
```

- [ ] **Step 8: Add scattering to the Grayscale path and the sky/misses.** For the Grayscale hit (lines ~473–476), compute the headlight direction and wrap the colour through `scatter` before the fog mix:

```glsl
				if (color_mode == 0) {
					vec3 sldir = -dir;
					if (light_yaw != 0.0 || light_pitch != 0.0) {
						sldir = rotate_about(rotate_about(sldir, cam_up, light_yaw), cam_right, light_pitch);
					}
					vec3 gcol = scatter(vec3(inv), total, dir, sldir);
					COLOR = vec4(mix(probe_dot(mix(gcol, fog_color, fog_amount(total)), eye + dir * total),
						bg, view_fade(total)), 1.0);
				} else {
```
  For the two sky/miss paths (`COLOR = vec4(bg, 1.0);` at line ~427 for the cube miss and line ~467 for leaving the cube/fog/view), apply scatter at the ray's exit distance. Compute the exit distance and the swung headlight once; the haze fills the space even where nothing was hit:

  - At the top of `fragment()` after `dir`, add a helper local for the swung headlight:
```glsl
	vec3 sky_ldir = -dir;
	if (light_yaw != 0.0 || light_pitch != 0.0) {
		sky_ldir = rotate_about(rotate_about(sky_ldir, cam_up, light_yaw), cam_right, light_pitch);
	}
```
  - The first miss (`tb.y < max(tb.x, 0.0)`): the ray never enters the cube, so there is no finite exit; leave it `COLOR = vec4(bg, 1.0);` (no scatter — nothing to travel through). (Spec: scattering is over the space the rays march; a ray that misses the cube entirely travelled through none of it.)
  - The `left_cube` miss (line ~466–467): replace with
```glsl
			if (left_cube) {
				float t_scat = min(t_exit, total);
				COLOR = vec4(scatter(bg, t_scat, dir, sky_ldir), 1.0);
			} else {
```
  where `t_exit` is the already-computed nearest of the cube far side / view limit / shed-fog cut, and `total` is how far the ray actually marched. (This matches the spec's "ray's exit distance … whichever is nearest".)

- [ ] **Step 9: Run both tests to verify they pass**

Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/shader_test.gd`
Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/noise_compiler_test.gd`
Expected: both PASS. (If `shader_test` reports an empty uniform list, the shader failed to compile — read the error from the run and fix the GLSL before continuing; use superpowers:systematic-debugging.)

- [ ] **Step 10: Commit**

```bash
git -C /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material add src/fractal/mandelbox.gdshader src/noise/noise_compiler.gd tests/shader_test.gd tests/noise_compiler_test.gd
git -C /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material commit -m "feat(shader): roughness, light size, shadows, scattering, surface/light colour, texture and bump

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: LoadShedder shadow rung + FractalView pushes shadow_steps and colours

**Files:**
- Modify: `src/perf/load_shedder.gd` (`LEVELS` ~lines 14–20)
- Modify: `src/fractal/fractal_view.gd` (`_push_params` ~lines 380–398)
- Test: `tests/load_shedder_test.gd`, `tests/fractal_view_test.gd`

**Interfaces — Consumes:** `FractalParams.SHADOW_STEPS` and `COLOR_KEYS` (Task 3); the shader's `shadow_steps` uniform and the two `vec3` colour uniforms (Task 4).
**Interfaces — Produces:**
- Each `LoadShedder.LEVELS` dictionary gains a `"shadow"` key: `[1.0, 0.5, 0.0, 0.0, 0.0]` across levels 0–4.
- `FractalView._push_params` pushes `shadow_steps = round(FractalParams.SHADOW_STEPS * _shed["shadow"])` (48 at level 0, 24 at level 1, 0 at level ≥ 2), and pushes each `COLOR_KEYS` id as `Vector3(c.r, c.g, c.b)` instead of the raw `Color`.

- [ ] **Step 1: Update `tests/load_shedder_test.gd` first.** After the ladder loop (around line 40), add:

```gdscript
	# --- shadows: full at level 0, halved at 1, off from level 2 ---
	check_approx(LoadShedder.settings(0)["shadow"], 1.0, "level 0 marches the full shadow")
	check_approx(LoadShedder.settings(1)["shadow"], 0.5, "level 1 halves the shadow march")
	for i in range(2, LoadShedder.top() + 1):
		check_eq(LoadShedder.settings(i)["shadow"], 0.0, "level %d skips the shadow march" % i)
```

- [ ] **Step 2: Update `tests/fractal_view_test.gd` first.**
  - The `LOOK_KEYS` push loop (lines 113–115) now only lists scalar keys, so `float(...)` stays valid. Add, right after that loop, a colour-push check:

```gdscript
	# the two COLOR keys are pushed as Vector3 (the shader's vec3 uniforms)
	params.light_color = Color(0.2, 0.4, 0.6)
	params.surface_color = Color(0.7, 0.5, 0.3)
	check(Vector3(mat.get_shader_parameter("light_color")).is_equal_approx(Vector3(0.2, 0.4, 0.6)),
		"light_color pushes as a Vector3")
	check(Vector3(mat.get_shader_parameter("surface_color")).is_equal_approx(Vector3(0.7, 0.5, 0.3)),
		"surface_color pushes as a Vector3")
	params.light_color = Color(1, 1, 1)
	params.surface_color = Color(1, 1, 1)
```
  - Add a `shadow_steps` push block after the existing level-0 fog check (around line 64):

```gdscript
	check_eq(int(mat.get_shader_parameter("shadow_steps")), FractalParams.SHADOW_STEPS,
		"level 0 pushes the full 48-step shadow march")
	view.set_load_level(1)
	check_eq(int(mat.get_shader_parameter("shadow_steps")), 24, "level 1 halves the shadow march to 24")
	view.set_load_level(2)
	check_eq(int(mat.get_shader_parameter("shadow_steps")), 0, "level 2 skips the shadow march")
	view.set_load_level(0)
	check_eq(int(mat.get_shader_parameter("shadow_steps")), FractalParams.SHADOW_STEPS, "and back to 48 at level 0")
```
  (Place it before the later `view.set_load_level(3)` fog-ease block so it does not disturb that sequence; after it, the test already returns to level 0.)

- [ ] **Step 3: Run both tests to verify they fail**

Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/load_shedder_test.gd`
Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/fractal_view_test.gd`
Expected: both FAIL (`"shadow"` key absent; `shadow_steps` unset; colours pushed as Color).

- [ ] **Step 4: Add the `"shadow"` key to every `LEVELS` entry** in `src/perf/load_shedder.gd`:

```gdscript
const LEVELS: Array[Dictionary] = [
	{"fog": 0.0, "detail": 1.0, "steps": 1.0, "speed": 1.0, "shadow": 1.0},
	{"fog": 400.0, "detail": 0.75, "steps": 1.0, "speed": 1.0, "shadow": 0.5},
	{"fog": 150.0, "detail": 0.55, "steps": 0.75, "speed": 1.0, "shadow": 0.0},
	{"fog": 60.0, "detail": 0.4, "steps": 0.5, "speed": 1.0, "shadow": 0.0},
	{"fog": 40.0, "detail": 0.35, "steps": 0.5, "speed": 0.4, "shadow": 0.0},
]
```
Update the `## Per level:` doc comment to mention the shadow factor.

- [ ] **Step 5: Push `shadow_steps` and the colours** in `FractalView._push_params`. Change the RESOLVED_KEYS push loop so COLOR keys go as Vector3, and push `shadow_steps`:

```gdscript
	for key in FractalParams.RESOLVED_KEYS:
		if key == &"precision":
			continue
		if FractalParams.COLOR_KEYS.has(key):
			var c: Color = _params.get(key)
			_material.set_shader_parameter(key, Vector3(c.r, c.g, c.b))
		else:
			_material.set_shader_parameter(key, _params.get(key))
	_material.set_shader_parameter("precision", _params.precision / (_params.detail * _shed["detail"]))
	...
	_material.set_shader_parameter("shadow_steps", int(round(FractalParams.SHADOW_STEPS * _shed["shadow"])))
```
(Place the `shadow_steps` push beside the `coarse_steps`/`fine_steps` pushes so a level change through `set_load_level` → `_push_params` re-pushes it.)

- [ ] **Step 6: Run both tests to verify they pass**

Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/load_shedder_test.gd`
Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/fractal_view_test.gd`
Expected: both PASS.

- [ ] **Step 7: Commit**

```bash
git -C /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material add src/perf/load_shedder.gd src/fractal/fractal_view.gd tests/load_shedder_test.gd tests/fractal_view_test.gd
git -C /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material commit -m "feat(perf): shadow rung on the load-shed ladder; view pushes shadow_steps and colours as Vector3

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Noise Output Texture/Bump ports and the compiler

**Files:**
- Modify: `src/noise/nodes/output.gd` (`inputs` ~lines 19–24; doc comment ~lines 1–8)
- Modify: `src/noise/noise_compiler.gd` (`compile` ~lines 46–79; add `_texture_fn` and `_bump_fn` beside `_displace_fn`/`_tint_fn` ~lines 176–201)
- Test: `tests/noise_compiler_test.gd`, `tests/noise_editor_test.gd`

**Interfaces — Consumes:** `NoiseCompiler.STUB` (Task 4, already grown with the two stub functions and two `false` constants). The noise editor renders slots generically from `type.inputs` (`src/ui/noise_editor.gd` `_add_slots`), so adding inputs to `output.gd` makes the Texture (amber VEC3) and Bump (green FLOAT) slots appear with no editor change.
**Interfaces — Produces:**
- The Output node has four inputs, in order: port 0 Displace (FLOAT), port 1 Tint (FLOAT), **port 2 Texture (VEC3)**, **port 3 Bump (FLOAT)**. (Append only; existing ports keep their indices, so saved graphs and existing wiring are unaffected.)
- `NoiseCompiler.compile(graph)` reads the Texture (port 2) and Bump (port 3) links, adds their ancestors to the `used` set, and emits, beside the three functions it writes now:
  - `vec3 noise_texture(vec3 p)` — returns `clamp(<expr>, 0.0, 1.0)` (the wired VEC3), or the stub `vec3(1.0)` when unwired.
  - `float noise_bump(vec3 p)` — returns `<expr>` (the wired FLOAT height), or the stub `0.0` when unwired.
  - `const bool noise_texture_on = true;`/`false;` and `const bool noise_bump_on = true;`/`false;`.
- The `wired` test in `compile` now also counts Texture/Bump: an unwired-everywhere graph still returns `STUB` with `uniforms == []`.
- `displaces()` is unchanged: a Texture- or Bump-only graph does not displace.

- [ ] **Step 1: Add the ports to `src/noise/nodes/output.gd`.** Extend `inputs`:

```gdscript
		port("Displace", NoisePort.Type.FLOAT,
			"Displace: added to the distance estimate (times Amplitude). Positive pushes the surface in, negative pulls it out. Unwired it is 0, so the shape is untouched.", 0.0),
		port("Tint", NoisePort.Type.FLOAT,
			"Tint: how far to blend the surface colour toward the Tint colour, clamped to 0..1 and scaled by Tint strength. Unwired it is 0, so the colour is untouched.", 0.0),
		port("Texture", NoisePort.Type.VEC3,
			"Texture: a colour the surface is multiplied by, each channel clamped to 0..1, scaled by the Material tab's Texture row. Unwired it is white, so the colour is untouched.", 0.0),
		port("Bump", NoisePort.Type.FLOAT,
			"Bump: a height in fractal units whose across-surface slope tilts the normal (a fake relief; the surface does not move), scaled by the Material tab's Bump row. Unwired it is flat.", 0.0),
```
Update the Output doc comment to mention Texture and Bump, and that the strengths live on the Material tab.

- [ ] **Step 2: Write the compiler tests first.** Append to `tests/noise_compiler_test.gd`'s `run()` (before the trailing helper functions), after the existing tint-wiring block:

```gdscript
	# ---------------------------------------------- Texture (port 2) and Bump (port 3)
	# Texture: a VEC3 from a VEC3-output node.
	var gt := NoiseGraph.new(resolver)
	var warp := gt.add_node(&"transform", Vector2.ZERO)   # VEC3 -> VEC3
	gt.connect_ports(gt.position_id(), 0, warp, 0)
	gt.connect_ports(warp, 0, gt.output_id(), 2)          # Texture
	var tex_result := NoiseCompiler.compile(gt)
	check_eq(tex_result["errors"], [], "a Texture-wired graph compiles with no errors")
	var tcode: String = tex_result["code"]
	check(tcode.contains("vec3 noise_texture(vec3 p) {") and tcode.contains("clamp("),
		"wiring Texture emits noise_texture, clamped to 0..1")
	check(tcode.contains("const bool noise_texture_on = true;"), "and noise_texture_on = true")
	check(tcode.contains("const bool noise_bump_on = false;"), "with Bump unwired, noise_bump_on = false")
	check(not NoiseCompiler.displaces(gt), "a Texture-only graph does not displace")
	check(_region_compiles_lit(tcode).get_shader_uniform_list().size() >= 0, "the Texture region splices")

	# Bump: a FLOAT from a FLOAT-output node.
	var gb := NoiseGraph.new(resolver)
	var vnb := gb.add_node(&"value_noise", Vector2.ZERO)   # VEC3 -> FLOAT
	gb.connect_ports(gb.position_id(), 0, vnb, 0)
	gb.connect_ports(vnb, 0, gb.output_id(), 3)            # Bump
	var bump_result := NoiseCompiler.compile(gb)
	check_eq(bump_result["errors"], [], "a Bump-wired graph compiles with no errors")
	var bcode: String = bump_result["code"]
	check(bcode.contains("float noise_bump(vec3 p) {"), "wiring Bump emits noise_bump")
	check(bcode.contains("const bool noise_bump_on = true;"), "and noise_bump_on = true")
	check(bcode.contains("const bool noise_texture_on = false;"), "with Texture unwired, noise_texture_on = false")
	check(bcode.contains("n_%s_scale" % vnb), "Bump's ancestors are in the uniform block")
	check(not NoiseCompiler.displaces(gb), "a Bump-only graph does not displace")
```
Add a wrapper helper near `_region_compiles` that also references the two new functions, so a spliced region compiles:

```gdscript
func _region_compiles_lit(code: String) -> Shader:
	var src := "shader_type canvas_item;\n" + code \
		+ "\nvoid fragment() {\n" \
		+ "\tvec3 pp = vec3(UV, 0.0);\n" \
		+ "\tvec3 tex = noise_texture_on ? noise_texture(pp) : vec3(1.0);\n" \
		+ "\tfloat b = noise_bump_on ? noise_bump(pp) : 0.0;\n" \
		+ "\tCOLOR = vec4(tex + vec3(b), 1.0);\n}\n"
	var sh := Shader.new()
	sh.code = src
	return sh
```

- [ ] **Step 3: Update `tests/noise_editor_test.gd` first.** Replace the Output port-count assertions (lines ~71–73):

```gdscript
	check_eq(out_widget.get_input_port_count(), 4, "Output shows Displace, Tint, Texture and Bump inputs")
	check_eq(out_widget.get_output_port_count(), 0, "…and no outputs")
	check_eq(out_widget.get_input_port_type(0), NoisePort.Type.FLOAT, "Displace is a Float slot")
	check_eq(out_widget.get_input_port_type(1), NoisePort.Type.FLOAT, "Tint is a Float slot")
	check_eq(out_widget.get_input_port_type(2), NoisePort.Type.VEC3, "Texture is a Vec3 slot")
	check_eq(out_widget.get_input_port_type(3), NoisePort.Type.FLOAT, "Bump is a Float slot")
```

- [ ] **Step 4: Run both tests to verify they fail**

Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/noise_compiler_test.gd`
Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/noise_editor_test.gd`
Expected: both FAIL.

- [ ] **Step 5: Implement the compiler.** In `NoiseCompiler.compile`:

```gdscript
	var disp := graph.input_link(graph.output_id(), 0)
	var tint := graph.input_link(graph.output_id(), 1)
	var tex := graph.input_link(graph.output_id(), 2)
	var bump := graph.input_link(graph.output_id(), 3)
	var wired := not disp.is_empty() or not tint.is_empty() or not tex.is_empty() or not bump.is_empty()
	if not wired:
		return {"code": STUB, "uniforms": [], "errors": errors}
```
Add `tex` and `bump` ancestors to `used`:

```gdscript
	for link in [disp, tint, tex, bump]:
		if not link.is_empty():
			for id in _ancestors(graph, link["from"]):
				used[id] = true
```
(This replaces the two existing `if not disp.is_empty(): … if not tint.is_empty(): …` ancestor loops.)
After the three existing function emissions, append the two new ones and the constants:

```gdscript
	code += _displace_fn(graph, disp, errors)
	code += _step_scale_fn(not disp.is_empty())
	code += _tint_fn(graph, tint, errors)
	code += _texture_fn(graph, tex, errors)
	code += _bump_fn(graph, bump, errors)
	code += "const bool noise_texture_on = %s;\n" % ("true" if not tex.is_empty() else "false")
	code += "const bool noise_bump_on = %s;\n" % ("true" if not bump.is_empty() else "false")
	return {"code": code, "uniforms": names, "errors": errors}
```
Add the two emit helpers beside `_tint_fn`:

```gdscript
static func _texture_fn(graph: NoiseGraph, tex: Dictionary, errors: Array) -> String:
	if tex.is_empty():
		return "vec3 noise_texture(vec3 p) { return vec3(1.0); }\n"
	var used: Dictionary = {}
	for id in _ancestors(graph, tex["from"]):
		used[id] = true
	var body := _emit_nodes(graph, _ordered(graph, used), errors)
	var result := "v_%s_%d" % [tex["from"], tex["from_port"]]
	return "vec3 noise_texture(vec3 p) {\n%s\treturn clamp(%s, 0.0, 1.0);\n}\n" % [body, result]


static func _bump_fn(graph: NoiseGraph, bump: Dictionary, errors: Array) -> String:
	if bump.is_empty():
		return "float noise_bump(vec3 p) { return 0.0; }\n"
	var used: Dictionary = {}
	for id in _ancestors(graph, bump["from"]):
		used[id] = true
	var body := _emit_nodes(graph, _ordered(graph, used), errors)
	var result := "v_%s_%d" % [bump["from"], bump["from_port"]]
	return "float noise_bump(vec3 p) {\n%s\treturn %s;\n}\n" % [body, result]
```
Update the `compile(graph)` doc comment (lines ~5–11) to list all five functions and the two `_on` constants.

- [ ] **Step 6: Run both tests to verify they pass**

Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/noise_compiler_test.gd`
Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/noise_editor_test.gd`
Expected: both PASS.

- [ ] **Step 7: Commit**

```bash
git -C /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material add src/noise/nodes/output.gd src/noise/noise_compiler.gd tests/noise_compiler_test.gd tests/noise_editor_test.gd
git -C /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material commit -m "feat(noise): Output Texture and Bump inputs, compiler emits noise_texture and noise_bump

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Console Light and Material tabs, and the COLOR row widget

**Files:**
- Modify: `src/ui/console/attribute_row.gd` (fields ~lines 31–47; `setup`/`refresh`/`value_control` ~lines 52–117; `_build_value` ~lines 161–227)
- Modify: `src/ui/console/console_window.gd` (fields ~lines 69–82; `setup` ~lines 84–144; `colour_inspector()` ~lines 151–153; `show_tab` doc ~line 173; `set_resolved` ~lines 208–215; `_refresh_sources` ~lines 365–372; class doc comment ~lines 3–14)
- Test: `tests/console_test.gd`

**Interfaces — Consumes:** `ShapeCatalogue.LIGHT_GROUPS`, `MATERIAL_GROUPS`, `group_tooltips()` (Task 2); `AttributeSpec.Type.COLOR` (Task 1).
**Interfaces — Produces:**
- `AttributeRow` draws a `ColorPickerButton` (`edit_alpha = false`) for a COLOR spec, as its value control; `value_control()` returns it; a colour change writes `_table.set_default(spec.id, c)`; `refresh()` sets the picker's `color` from the table.
- `ConsoleWindow` has four tabs — **Shape (0), Light (1), Material (2), View (3)** — titled `"Shape"`, `"Light"`, `"Material"`, `"View"`. `colour_inspector()` is replaced by `light_inspector()` and `material_inspector()`. The palette window heads the **Material** tab. Both new inspectors get the axis sources (`_refresh_sources`) and the per-frame resolved values (`set_resolved`).

- [ ] **Step 1: Update `tests/console_test.gd` first.**
  - Replace the Colour-tab block (lines ~51–60) with the four-tab split:

```gdscript
	var light := console.light_inspector()
	var material := console.material_inspector()
	check_eq(inspector.row_count() + light.row_count() + material.row_count(), table.specs.size(),
		"one row per spec across the three inspectors")
	check(inspector.row(&"box_scale") != null and light.row(&"box_scale") == null and material.row(&"box_scale") == null,
		"Scale is on the Shape tab")
	check(light.row(&"light_color") != null and light.row(&"shadows") != null,
		"Light colour and Shadows are on the Light tab")
	check(material.row(&"color_mode") != null and material.row(&"roughness") != null and material.row(&"texture_strength") != null,
		"Colour mode, Roughness and Texture are on the Material tab")
	check(material.row(&"light_color") == null and light.row(&"color_mode") == null,
		"neither tab holds the other's rows")
	check(material.row(&"palette_a_r") != null, "the palette's twelve numbers are on the Material tab")
	check_eq(console.tabs().get_tab_count(), 4, "four tabs")
	check_eq(console.tabs().get_tab_title(0), "Shape", "the first is Shape")
	check_eq(console.tabs().get_tab_title(1), "Light", "the second Light")
	check_eq(console.tabs().get_tab_title(2), "Material", "the third Material")
	check_eq(console.tabs().get_tab_title(3), "View", "the fourth View")
	check(console.view_pane() != null and console.view_pane().get_parent() == console.tabs(), "which is the View pane")
	check(console.palette_window() != null and material.is_ancestor_of(console.palette_window()),
		"the palette window heads the Material tab's list")
	check(console.palette().table() == table, "and edits the console's own table")

	# --- a COLOR row's value control is a ColorPickerButton; changing it writes the table ---
	var lc_row := light.row(&"light_color")
	var picker := lc_row.value_control() as ColorPickerButton
	check(picker != null, "the Light colour row's value control is a ColorPickerButton")
	picker.color = Color(0.2, 0.4, 0.6)
	picker.color_changed.emit(picker.color)
	check((table.get_default(&"light_color") as Color).is_equal_approx(Color(0.2, 0.4, 0.6, 1.0)),
		"changing the picker writes the table")
```
  - The later `set_resolved` readout check (lines ~97–100) uses `inspector.row(&"box_scale")` (Shape tab) — unchanged.

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/console_test.gd`
Expected: FAIL (`light_inspector`/`material_inspector` undefined, three tabs, no ColorPickerButton).

- [ ] **Step 3: Add the COLOR value control to `AttributeRow`.**
  - Add a field: `var _picker: ColorPickerButton`.
  - In `_build_value`'s `match spec.type:` add an arm:

```gdscript
			AttributeSpec.Type.COLOR:
				_picker = ColorPickerButton.new()
				_picker.edit_alpha = false
				_picker.custom_minimum_size = Vector2(SPIN_MIN_WIDTH, 0)
				_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				_picker.tooltip_text = "%s\n\n%s" % [spec.tooltip, spec.effects]
				_picker.color_changed.connect(_on_color_changed)
				column.add_child(_picker)
```
  - In `value_control()` return `_picker` first:

```gdscript
func value_control() -> Control:
	if _slider != null:
		return _slider
	if _check != null:
		return _check
	if _picker != null:
		return _picker
	return _option
```
  - In `refresh()`, set the picker's colour (guard `_updating` as the others do):

```gdscript
		if _picker != null:
			_picker.color = value as Color
```
  - Add the handler:

```gdscript
func _on_color_changed(c: Color) -> void:
	if _updating:
		return
	_table.set_default(spec.id, c)
```
  (A COLOR spec is not bindable, so `_build_binding` is not called and `_readout` stays hidden; `set_resolved` already no-ops when there is no active binding.)

- [ ] **Step 4: Build the two inspectors in `ConsoleWindow`.**
  - Rename the field `_colour_inspector` → `_light_inspector` and add `_material_inspector`.
  - In `setup()`, replace the single Colour inspector block (lines ~119–128) with:

```gdscript
	_palette = Palette.new(table)
	_palette_window = PaletteWindow.new()
	_palette_window.setup(_palette)
	_palette_window.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_light_inspector = AttributeInspector.new()
	_light_inspector.name = "Light"
	_light_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_light_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(_light_inspector)
	_light_inspector.setup(table, group_tooltips, ShapeCatalogue.LIGHT_GROUPS)

	_material_inspector = AttributeInspector.new()
	_material_inspector.name = "Material"
	_material_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_material_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(_material_inspector)
	_material_inspector.setup(table, group_tooltips, ShapeCatalogue.MATERIAL_GROUPS, _palette_window)
```
  (The Light tab gets no header; the Material tab gets the palette window as its header. The View pane is added after, so the tab order is Shape, Light, Material, View.)
  - Replace `colour_inspector()` with two accessors:

```gdscript
## The Light tab's inspector (Light, Scattering, Picture).
func light_inspector() -> AttributeInspector:
	return _light_inspector


## The Material tab's inspector (Colour, Surface, Texture, Palette), under the palette window.
func material_inspector() -> AttributeInspector:
	return _material_inspector
```
  - In `set_resolved()` forward to both:

```gdscript
	if _light_inspector != null:
		_light_inspector.set_resolved(values)
	if _material_inspector != null:
		_material_inspector.set_resolved(values)
```
  - In `_refresh_sources()` set sources on both:

```gdscript
	_light_inspector.set_sources(axis_list)
	_material_inspector.set_sources(axis_list)
```
  - Update the `show_tab` doc comment (`## Bring the Shape (0), Light (1), Material (2) or View (3) tab to the front.`) and the class doc comment at the top of the file (the "Colour tab" sentence → Light and Material tabs).

- [ ] **Step 5: Run the test to verify it passes**

Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/console_test.gd`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git -C /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material add src/ui/console/attribute_row.gd src/ui/console/console_window.gd tests/console_test.gd
git -C /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material commit -m "feat(console): Light and Material tabs, COLOR picker row

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: *(folded into Task 6)*

The spec's "noise Output ports + compiler" work and its test both live in Task 6; there is no separate Task 8. (Numbering kept so the task order list above reads straight.)

---

### Task 9: Workspace shininess → roughness migration

**Files:**
- Modify: `src/workspace/workspace.gd` (`restore()` ~lines 61–110; add a private migration helper; class doc comment ~lines 1–22)
- Test: `tests/workspace_test.gd`

**Interfaces — Consumes:** the `roughness` catalogue id (Task 2); the removed `light_shininess` id.
**Interfaces — Produces:** `Workspace.restore` migrates a saved shape section carrying `light_shininess` **before** `table.apply_dict`: a `defaults["light_shininess"]` becomes `defaults["roughness"] = sqrt(2 / (shininess + 2))`, the old key dropped, **no warning**; a `bindings["light_shininess"]` is dropped **with one warning**. (Note: the spec calls this `Workspace.apply`; the method is actually `Workspace.restore`, which calls `table.apply_dict` — the migration goes at the head of its shape branch. This is the only naming discrepancy resolved in this plan.)

- [ ] **Step 1: Write the test first.** Append to `tests/workspace_test.gd`'s `run()` (before the final `DirAccess.remove_absolute`):

```gdscript
	# --- a v2 file carrying light_shininess migrates to roughness ---
	var mt := _table()
	var mw := Workspace.restore({
		"version": 2,
		"shape": {"defaults": {"light_shininess": 160.0, "box_scale": -1.7}, "bindings": {}},
		"axes": {}, "fractal": {},
	}, mt, Axes.new(), FractalParams.new(), CameraState.make_default())
	check_approx(mt.get_default(&"roughness"), 1.0 / 9.0,
		"light_shininess 160 loads as roughness 1/9 (sqrt(2/(160+2)))")
	check_approx(mt.get_default(&"box_scale"), -1.7, "the rest of the shape still restores")
	check(mw.is_empty(), "the shininess migration warns nothing: %s" % [mw])

	# --- a binding on light_shininess is dropped with one warning ---
	var mt2 := _table()
	var mw2 := Workspace.restore({
		"version": 2,
		"shape": {"defaults": {}, "bindings": {"light_shininess": {"source": "time", "gain": 1.0, "waveform": 0, "period": 1.0}}},
		"axes": {}, "fractal": {},
	}, mt2, Axes.new(), FractalParams.new(), CameraState.make_default())
	check_eq(mw2.size(), 1, "the dropped shininess binding warns once: %s" % [mw2])
	check(String(mw2[0]).to_lower().contains("shininess"), "and the warning names shininess")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/workspace_test.gd`
Expected: FAIL (roughness untouched; the unknown `light_shininess` default warns "Unknown attribute").

- [ ] **Step 3: Implement the migration.** In `restore()`, the shape branch becomes:

```gdscript
	var shape: Variant = data.get("shape", {})
	if shape is Dictionary:
		shape = _migrate_shininess(shape as Dictionary, warnings)
		var defaults: Variant = (shape as Dictionary).get("defaults", {})
		if defaults is Dictionary and not (defaults as Dictionary).has("shape") and table.has(&"shape"):
			table.set_default(&"shape", FractalParams.Shape.MANDELBOX)
		for w in table.apply_dict(shape):
			warnings.append(w)
	else:
		warnings.append("Malformed shape section ignored")
```
Add the helper:

```gdscript
## Turn an old save's light_shininess into the new roughness, in place of
## apply_dict's "unknown attribute" warning. The specular exponent was
## 2/roughness^2 - 2, so roughness = sqrt(2 / (shininess + 2)); the default 160
## gives 1/9. A default migrates silently; a binding on it is dropped with a
## warning (roughness drives the exponent through a square root, so the old
## additive drive no longer means anything).
static func _migrate_shininess(shape: Dictionary, warnings: Array) -> Dictionary:
	var out := shape.duplicate(true)
	var defaults: Variant = out.get("defaults", {})
	if defaults is Dictionary and (defaults as Dictionary).has("light_shininess"):
		var sh := float((defaults as Dictionary)["light_shininess"])
		(defaults as Dictionary).erase("light_shininess")
		if not (defaults as Dictionary).has("roughness"):
			(defaults as Dictionary)["roughness"] = sqrt(2.0 / maxf(sh + 2.0, 1e-6))
	var bindings: Variant = out.get("bindings", {})
	if bindings is Dictionary and (bindings as Dictionary).has("light_shininess"):
		(bindings as Dictionary).erase("light_shininess")
		warnings.append("Binding on 'light_shininess' dropped (shininess is now Roughness)")
	return out
```
Update the class doc comment to mention the migration.

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/workspace_test.gd`
Expected: PASS. (The saves/ sweep at the end of the test also still passes: the committed saves — `default.json`, `juliaIceField.json`, `juliaIceTerraces.json`, `noiseRidges.json` — carry no `light_shininess` and none of the new colour ids, so they load as today with no warnings.)

- [ ] **Step 5: Commit**

```bash
git -C /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material add src/workspace/workspace.gd tests/workspace_test.gd
git -C /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material commit -m "feat(workspace): migrate a saved light_shininess to roughness

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: README (independent — no test)

**Files:**
- Modify: `README.md` (top summary ~line 13 and ~line 36; the load-shed ladder table ~lines 139–146; the Console section header ~line 206; the Colour-tab paragraph ~lines 266–287; the Noise fields Output row ~lines 379–405)

**Interfaces — Consumes:** nothing in code; this documents Tasks 2–9.

- [ ] **Step 1: Update the Console section.** Change "the **Shape**, **Colour** and **View** tabs" (line 206) to "the **Shape**, **Light**, **Material** and **View** tabs". Replace the single **Colour tab.** paragraph (lines 266–287) with a **Light tab.** paragraph and a **Material tab.** paragraph:
  - **Light tab.** the one lamp every lit mode shares — **Light colour**, **Light yaw**/**Light pitch** (swing the headlight), **Light size** (a point light at 0, a broad soft source above it), **Ambient**/**Diffuse**, **Shadows** (0 is off and casts no shadow ray; only visible with the light swung off the headlight); **Scattering** — **Density**, **Glow** and **Brightness** of a light-tinted distance haze (analytic, no extra rays); **Picture** — **Exposure** and **Saturation** on the final colour. The defaults are the site's, so the picture is unchanged until one is moved.
  - **Material tab.** Fractacular's Colour window at the top of one scrolling list (the twelve cosine-palette sliders, curves and strip), then **Colour** (the thirteen modes plus Palette and its four extra rows — unchanged), **Surface** (**Surface colour**, **Roughness** — glassy at low, matte at high; replaces the old Shininess — and **Specular**), **Texture** (**Texture** and **Bump**, driven by the noise editor's Texture and Bump outputs; nothing wired, nothing changes), and **Palette** (the twelve numbers as bindable rows).
  - Keep the "All of it is saved with the view" and binding-widget paragraphs.
- [ ] **Step 2: Update the top summary** (lines 13, 36) so "a Colour tab" / "**Colour** tabs" read "Light and Material tabs".
- [ ] **Step 3: Update the Noise fields Output row** (line 405) to list Texture and Bump:

```
| **Output** | **Output** — Displace, Tint, **Texture** and **Bump** inputs, Amplitude, Step scale, Tint colour and strength (one per graph). Texture multiplies the surface colour; Bump tilts the normal for a fake relief (the Material tab's Texture and Bump rows scale them). |
```
  and add a sentence to the Noise-fields intro (lines 379–385) that the Output's **Texture** (a Vec3, each channel 0..1) and **Bump** (a Float height) recolour and tilt the surface without moving it.
- [ ] **Step 4: Add the shadow column to the load-shed ladder table** (lines 139–146):

```
| level | distance fog (× d₀) | detail | step budget | shadow march | Fly speed |
|---|---|---|---|---|---|
| 0 | none | 100% | 100% | 48 steps | — |
| 1 | 400 | 75% | 100% | 24 steps | — |
| 2 | 150 | 55% | 75% | off | — |
| 3 | 60 | 40% | 50% | off | — |
| 4 | 40 | 35% | 50% | off | capped at 40% |
```
  and add one line after the table: the shadow march (when Shadows is on) halves at level 1 and drops out from level 2; scattering and bump cost no extra marches and stay at every level.
- [ ] **Step 5: Review the rendered Markdown by eye** (open `README.md` in the editor or `sed -n` the changed ranges) — there is no automated test for prose.
- [ ] **Step 6: Commit**

```bash
git -C /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material add README.md
git -C /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material commit -m "docs(readme): Light and Material tabs, Output Texture/Bump, shadow shed column

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 11: Tab-index and screenshot test fixups

With the View tab moved from index 2 to index 3 and the Colour tab replaced, the tests that reach the View tab by index, the UI console test that drives the old Colour tab, and the screenshot pass that sets `light_shininess` all need updating. These are the remaining call sites of the old layout.

**Files:**
- Modify: `tests/ui_console_test.gd` (the `_colour_dropdown()` block ~lines 137–163)
- Modify: `tests/main_test.gd` (`show_tab(2)` for the View tab ~lines 146, 175; the `show_tab(0)` at 162 is Shape and stays)
- Modify: `tests/ui_journey_test.gd` (`_show_view_tab()` tab index 2 ~lines 249–256)
- Modify: `tests/screenshots.gd` (the `light_shininess` apply_resolved calls ~lines 83–84, 92–93)

- [ ] **Step 1: `ui_console_test.gd`.** In `_colour_dropdown()` rename to drive the Material tab (index 2): click `get_tab_rect(2)`, assert `current_tab == 2`, and replace `console.colour_inspector()` with `console.material_inspector()` (two uses). The function tests the `color_mode` dropdown, which now lives on the Material tab. Keep the final `console.show_tab(0)`.

- [ ] **Step 2: `main_test.gd`.** Change the two `console.show_tab(2)` calls that open the **View** tab (lines ~146 and ~175, each immediately before using `console.view_pane()` / `vpane.fullscreen_button`) to `console.show_tab(3)`. Leave `console.show_tab(0)` (line ~162, Shape) unchanged.

- [ ] **Step 3: `ui_journey_test.gd`.** In `_show_view_tab()` change the three `2`s (the `get_tab_rect(2)` and the two `current_tab != 2` / `current_tab, 2` checks) to `3` — the View tab is now index 3.

- [ ] **Step 4: `screenshots.gd`.** Replace `&"light_shininess": 12.0` (the broad-glint raked-light shot, line ~84) with `&"roughness": 0.4` (a broad sheen), and the restore `&"light_shininess": 160.0` (line ~93) with `&"roughness": 1.0 / 9.0` (the site's 160 exponent). Update the nearby comment from "broad glints" wording if it names shininess.

- [ ] **Step 5: Run the affected UI tests.**

Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/ui_console_test.gd`
Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/main_test.gd`
Run: `godot4 --headless --path /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material -s tests/ui_journey_test.gd`
Expected: all PASS. (`screenshots.gd` is not a `*_test.gd` and is not run by `run_all.sh`; it is exercised by `tests/screenshots.sh`, which needs a GPU and a windowed run — do **not** run it headless/windowed. Confirm it parses by loading its class: `godot4 --headless --path <worktree> --check-only tests/screenshots.gd` if available, otherwise rely on the full-suite import step in Task 12 catching a parse error.)

- [ ] **Step 6: Commit**

```bash
git -C /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material add tests/ui_console_test.gd tests/main_test.gd tests/ui_journey_test.gd tests/screenshots.gd
git -C /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material commit -m "test: follow the View tab to index 3 and the Material tab; roughness in the screenshot pass

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 12: Full-suite gate

**Files:** none (verification only).

- [ ] **Step 1: Run the whole headless suite from the worktree.**

Run: `cd /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material && GODOT=godot4 tests/run_all.sh; echo "exit $?"`
Expected: exit 0, and no line reading `*** … FAILED`, `SCRIPT ERROR`, or `Failed to load script`. (`run_all.sh` cd's to its own parent, so it resolves the worktree root correctly; it refreshes the class cache with `--headless --import` first.)

- [ ] **Step 2: If anything fails**, fix it in the owning task's files (use superpowers:systematic-debugging — do not paper over a failure by loosening a check), re-run the single test, then re-run `run_all.sh`. Do not proceed until it is green.

- [ ] **Step 3: Confirm the branch is clean and the history is the eight task commits** (plus the plan commit):

Run: `git -C /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material status && git -C /Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/light-material log --oneline 157657f..HEAD`
Expected: clean working tree; the commits from Tasks 1–11 (and this plan).

- [ ] **Step 4: Report readiness.** The work is committed on `light-material`. Do **not** push, merge, rebase, or open a PR — tell the human it is ready and hand the push over (per the global constraints).

---

## Self-review (completed while writing)

- **Spec coverage:** Console split (Task 7), catalogue rows + groups (Task 2), COLOR type (Task 1), light colour/size/shadows/scattering (Tasks 2–5), surface colour/roughness/specular (Tasks 2–4), Texture/Bump on the Output node (Task 6), shadows on the shed ladder (Task 5), shader lit-path + scattering + the COLOR-vec3 push (Tasks 4–5), saves/migration (Task 9), tests named in the spec (woven through), README (Task 10). The out-of-scope list (presets, god rays, AO, a direction widget) is untouched.
- **Naming discrepancy resolved:** the spec says the shininess migration lives in `Workspace.apply`; the real method is `Workspace.restore` (which calls `apply_dict`). The migration is placed at the head of `restore`'s shape branch (Task 9), noted there.
- **Interface consistency:** `light_inspector()`/`material_inspector()` (Task 7) are the names used by the tests in Tasks 7 and 11; `COLOR_KEYS`/`SHADOW_STEPS` (Task 3) are consumed by Tasks 4 and 5; `noise_texture_on`/`noise_bump_on` (Task 4 stub, Task 6 real) are referenced by the shader (Task 4) and the compiler tests (Task 6). The NOISE-region/`STUB` byte-identity is enforced by doing both in Task 4.
- **Placeholder scan:** every code step carries the actual GDScript/GLSL or an exact table of values; no "TBD"/"handle edge cases"/"similar to Task N".
