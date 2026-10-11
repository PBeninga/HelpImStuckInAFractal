# Light and Material tabs — design

Split the console's Colour tab into a **Light** tab (the lamp: its colour,
direction, size, intensity, shadows, scattering, and the picture's exposure and
saturation) and a **Material** tab (the colour mode and palette, the surface's
colour, roughness and specular strength, and a texture and bump driven by the
noise editor). Every new control defaults to "no change", so every site colour
mode, every saved view and every existing noise graph renders bit-for-bit as
it does today.

Decisions taken with the user (2026-10-09): two tabs, Light and Material; light
"quality" is the lamp's size plus a cheap sense of volumetric scattering, where
the only extra sampling is a shadow ray; scattering is light-tinted distance
fog; the texture is colour and bump, each its own input on the noise editor's
Output node; the two colours are colour-picker rows; the texture and bump
strengths are Material rows; Exposure and Saturation end the Light tab; shadows
are hooked into the load-shed ladder.

## Console

Four tabs: **Shape** (0), **Light** (1), **Material** (2), **View** (3). The
Colour inspector becomes two `AttributeInspector`s over the one table, each
limited to its groups: `ShapeCatalogue.LIGHT_GROUPS` = Light, Scattering,
Picture; `ShapeCatalogue.MATERIAL_GROUPS` = Colour, Surface, Texture, Palette.
The palette window heads the Material tab's list, as it headed the Colour
tab's. `ConsoleWindow.colour_inspector()` is replaced by `light_inspector()`
and `material_inspector()`; `COLOUR_GROUPS` goes. Both inspectors get the
axis sources and the per-frame resolved values, as the Colour one did.

## Catalogue rows

Spec order is inspector order and `FractalParams.RESOLVED_KEYS` order; each
group is contiguous. Ids are the shader uniform names and the FractalParams
fields, as now. `light_shininess` is removed (see Roughness).

### Light tab

| id | label | type | default | slider | hard | group |
|---|---|---|---|---|---|---|
| `light_color` | Light colour | COLOR | white | | | Light |
| `light_yaw` | Light yaw | (moved, unchanged) | | | | Light |
| `light_pitch` | Light pitch | (moved, unchanged) | | | | Light |
| `light_size` | Light size | FLOAT | 0 | 0 … 30 (degrees) | 0 … 89 | Light |
| `light_ambient` | Ambient | (moved, unchanged) | | | | Light |
| `light_diffuse` | Diffuse | (moved, unchanged) | | | | Light |
| `shadows` | Shadows | FLOAT | 0 | 0 … 1 | | Light |
| `scatter_density` | Density | FLOAT | 0 | 0 … 0.5, step 0.001 | 0 … 10 | Scattering |
| `scatter_glow` | Glow | FLOAT | 0 | 0 … 0.95 | | Scattering |
| `scatter_brightness` | Brightness | FLOAT | 1 | 0 … 4 | 0 … 16 | Scattering |
| `exposure` | Exposure | (moved, unchanged) | | | | Picture |
| `saturation` | Saturation | (moved, unchanged) | | | | Picture |

### Material tab

| id | label | type | default | slider | hard | group |
|---|---|---|---|---|---|---|
| `color_mode`, `palette_source`, `palette_frequency`, `palette_offset`, `palette_occlusion` | (unchanged) | | | | | Colour |
| `surface_color` | Surface colour | COLOR | white | | | Surface |
| `roughness` | Roughness | FLOAT | 1/9 | 0.02 … 1, log | | Surface |
| `light_specular` | Specular | (moved, unchanged id) | | | | Surface |
| `texture_strength` | Texture | FLOAT | 1 | 0 … 1 | | Texture |
| `bump_strength` | Bump | FLOAT | 1 | 0 … 4 | 0 … 64 | Texture |
| the twelve `palette_*` rows | (unchanged) | | | | | Palette |

Every row has the usual plain-language tooltip and effects text. Group
tooltips: Light (the one lamp every lit mode shares, a headlight by default),
Scattering (haze in the space the camera flies through, analytic, no extra
rays), Picture (on the final colour), Surface (what the surface is made of),
Texture (the noise editor's Texture and Bump outputs; "nothing wired, nothing
changes; press N").

### The COLOR row type

`AttributeSpec.Type.COLOR`: value a `Color` (alpha ignored), `bindable` false,
no slider, spin box, readout or binding widgets. `sanitize` accepts a Color or
a 3- or 4-element Array (what JSON gives back) and returns a Color with alpha
1. `AttributeTable.to_dict` writes a COLOR value as `[r, g, b]` (Color is not
JSON); `apply_dict` goes through `set_default`, which sanitizes it back. The
row draws a `ColorPickerButton` (`edit_alpha` false, the row's value control)
and writes `color_changed` straight into the table; `refresh` sets the
picker's colour. The resolver passes a COLOR default through untouched (it is
not bindable).

`FractalParams` holds `light_color` and `surface_color` as `Color` fields. The
view pushes each as a `Vector3(r, g, b)` to the shader's `vec3` uniform
(`FractalParams.COLOR_KEYS` names them); every other key is pushed as it is.

### Roughness replaces Shininess

The specular exponent becomes `2 / r² − 2` for roughness `r`; the default
`1/9` gives exactly 160, the site's. The lamp's size widens the lobe:
`r_eff² = r² + radians(light_size)²`, so at size 0 the maths is the site's.
A saved view carrying `light_shininess` is migrated in `Workspace.apply`
before `apply_dict`: `roughness = sqrt(2 / (shininess + 2))`, the old key
dropped, no warning; a binding on `light_shininess` is dropped with a warning.

## Shader

New uniforms, each defaulted to its catalogue default so an unpushed frame is
right: `vec3 light_color`, `float light_size`, `float shadows`,
`int shadow_steps` (a renderer uniform, from the view, 0 = no shadow march),
`float scatter_density`, `float scatter_glow`, `float scatter_brightness`,
`vec3 surface_color`, `float roughness`, `float texture_strength`,
`float bump_strength`. `light_shininess` goes.

For a lit hit (every mode but Grayscale), in order:

1. **Normal** `n` as now (NF or true normal). Then, when the graph's Bump is
   wired (`noise_bump_on`) and `bump_strength != 0`: `g` = the central
   -difference gradient of `noise_bump(p)` at `v` with the normal's own
   `delta`; `n = normalize(n − bump_strength · (g − n · dot(n, g)))` (the
   gradient's part across the surface tilts the normal; a NaN guard keeps the
   old `n` when the result has no length).
2. **Light direction** `ldir` as now (toward the eye, swung by yaw and pitch).
3. **Shadow** `sh = 1`. When `shadows > 0`, `shadow_steps > 0` and the light
   is not the headlight (yaw or pitch non-zero, since a headlight's shadow ray
   retraces the view ray): `sh = mix(1, soft_shadow(…), shadows)`.
   `soft_shadow` marches from `v + n · 4ε` along `ldir` (ε = `hit_eps(total)`)
   with the coarse iteration count, at most `shadow_steps` steps (loop bound
   64), stopping at the cube's far side (`box_intersect`): a step with
   `d < ε` returns 0; otherwise `res = min(res, k · d / t)` with
   `k = 1 / tan(max(radians(light_size), radians(0.5)))`, so a size-0 lamp is
   near-hard and a wide one has a wide penumbra; `t += d · noise_step_scale()`.
   Returns `clamp(res, 0, 1)`.
4. **Light term** `lgt = sh · (light_diffuse · nl + light_specular · pow(nl, e)) + light_ambient`
   with `e = 2 / r_eff² − 2`, `nl = |n · ldir|` as now.
5. **Mode colour** `col` exactly as now from `lgt`, `n`, `ce`, `inv`.
6. **Texture**: when `noise_texture_on`, `col *= mix(vec3(1), noise_texture(v), texture_strength)`.
7. **Surface colour** `col *= surface_color` and **light colour**
   `col *= light_color`, each guarded by `!= vec3(1)` so the defaults stay
   bit-for-bit.
8. Exposure and saturation as now; then `noise_tint`, then **scattering**,
   then the shed fog, the probe dot and the view fade as now.

**Scattering** `scatter(col, t, dir, ldir)` for a hit at distance `t` and for a
miss at the ray's exit distance (the cube's far side, the view limit or the
shed fog's cut, whichever is nearest; `ldir` there is the headlight direction
`−dir` swung by yaw and pitch): off when `scatter_density <= 0`; else
`a = 1 − exp(−scatter_density · t / near_dist)` (near-distance units, like the
shed fog, so it means the same at every depth); `c = dot(dir, ldir)`;
`phase = HG(c, g) / HG(1, g)` with `g = scatter_glow` and
`HG(c, g) = (1 − g²) / (1 + g² − 2 g c)^1.5`, so glow 0 is a uniform haze and
glow near 1 a beam around the light's direction; `haze = light_color ·
scatter_brightness · phase`; `return mix(col, haze, a)`. It applies to
Grayscale and the sky too (the haze fills the space, not the surface).

The Grayscale path (mode 0) is otherwise untouched: no normal, no shadow, no
texture, no surface or light colour.

## Noise editor

The Output node gains two inputs after Tint: **Texture** (port 2, VEC3: the
colour the surface is multiplied by, each channel clamped to 0 … 1; unwired it
is white) and **Bump** (port 3, FLOAT: a height in fractal units whose slope
tilts the normal; unwired it is flat). The Output node's own parameters are
unchanged; the strengths are the Material rows.

`NoiseCompiler.compile` reads the two links, adds their ancestors to the used
set, and emits `vec3 noise_texture(vec3 p)` and `float noise_bump(vec3 p)`
beside the three functions it writes now, plus `const bool noise_texture_on`
and `const bool noise_bump_on` so the shader skips the four noise evaluations
when nothing is wired. The stub region (`STUB`, byte-identical to the base
shader's) grows the two stubs (`vec3(1.0)`, `0.0`) and the two `false`
constants. `displaces()`, `live_values()` and `is_live_param()` are unchanged;
a Texture- or Bump-only graph colours the surface without moving it.

## Load shedding

`LoadShedder.LEVELS` gains `"shadow"`: 1.0, 0.5, 0, 0, 0. The view pushes
`shadow_steps = round(FractalParams.SHADOW_STEPS × shed.shadow)` with
`SHADOW_STEPS = 48`, so level 1 halves the shadow march and level 2 and above
skip it. Scattering and bump cost no extra marches and stay at every level.
The README's ladder table gets the column.

## Saves

A view saves as now (shape version 2): the new ids in the defaults, colours as
`[r, g, b]`. A file from before this has none of them and loads as today's
picture, bar the shininess migration above. A noise graph with nothing on
ports 2 and 3 is unchanged on disk and in effect.

## Tests (headless)

- `shape_catalogue_test`: the new ids, defaults and ranges; roughness 1/9;
  `LIGHT_GROUPS` / `MATERIAL_GROUPS` cover the groups; `light_shininess` gone;
  COLOR specs are not bindable.
- `attribute_test`: a COLOR spec sanitizes an Array to a Color; `to_dict` /
  `apply_dict` round-trip a colour through JSON.
- `console_test`: four tabs titled Shape, Light, Material, View; Light colour
  and Shadows on the Light tab, Colour mode, Roughness and Texture on the
  Material tab, neither on the other; the palette window heads the Material
  tab; a COLOR row's value control is a `ColorPickerButton` and changing it
  writes the table.
- `shader_test`: compiles; the uniform set is the renderer uniforms (now with
  `shadow_steps`) plus the catalogue ids; a `vec3` uniform's source default
  matches a COLOR default.
- `noise_compiler_test`: an unwired graph is the stub (with the two `false`
  constants); wiring Texture emits `noise_texture` and `noise_texture_on =
  true`; wiring Bump emits `noise_bump`; neither displaces.
- `load_shedder_test` / `fractal_view_test`: the shadow factor per level, and
  the view pushing `shadow_steps` 48, 24, 0.
- `workspace_test`: a v2 file with `light_shininess` 160 loads as roughness
  1/9 with no warning.
- `ui_console_test` / `screenshots.gd`: the Colour-tab clicks become
  Material-tab clicks (tab 2).

## Docs

README: the Console section's Colour-tab paragraph becomes Light tab and
Material tab paragraphs; the Noise fields table's Output row lists Texture and
Bump; the load-shed ladder gains the shadow column. The systems viz's colour
pane is left for a follow-up.

## Out of scope

Texture presets (Clouds, Rock, Granite…) as stock noise graphs; sampled
volumetrics (god rays); ambient occlusion; a direction widget.
