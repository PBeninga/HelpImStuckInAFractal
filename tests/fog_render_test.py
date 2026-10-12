#!/usr/bin/env python3
"""Exercise the actual fog/march shader in headless Chrome's WebGL2 renderer.

No Python packages required. Set CHROME to override the Chrome executable.
Godot syntax is adapted to GLSL; a plane distance field replaces de_scene so
we can count queries and detect any query/shading beyond the wall. Everything
else, including both march phases, fog compositing and shadows, is repo code.
Scratch files and Chrome's isolated profile stay in the system temp directory.
"""

import html
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
CHROME = os.environ.get("CHROME") or shutil.which("google-chrome") or shutil.which("chromium")
if not CHROME:
    CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


def function_body(source, signature, body):
    start = source.index("{", source.index(signature))
    depth = 1
    end = start + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[:start + 1] + body + source[end - 1:]


source = (ROOT / "src/fractal/mandelbox.gdshader").read_text()
source = re.sub(r'#include "res://([^\"]+)"', lambda m: (ROOT / m[1]).read_text(), source)
source = re.sub(r"^shader_type .*;", "", source, flags=re.M)
source = re.sub(r"(uniform sampler2D \w+)\s*:[^;]+;", r"\1;", source)
defaults = {}


def uniform_default(match):
    kind, name, value = match.groups()
    if kind == "vec3":
        defaults[name] = [float(v) for v in value[5:-1].split(",")]
    elif kind == "bool":
        defaults[name] = int(value == "true")
    else:
        defaults[name] = float(value)
    return f"uniform {kind} {name};"


source = re.sub(r"uniform (float|int|bool|vec3) (\w+) = ([^;]+);", uniform_default, source)
# Godot accepts this uniform name; raw GLSL reserves it as a qualifier.
source = re.sub(r"\bprecision\b", "shape_precision", source)
source = function_body(source, "float de_scene(", """
    test_calls++;
    if (fog_distance > 0.0 && length(off) >= fog_wall_distance()) { test_outside = 1.0; }
    which = 0;
    if (test_output == 2) { return test_stride; } // unobstructed shadow ray
    return min(abs(test_surface - off.x), test_stride);
""")
source = source.replace("// Step-count shading stays", "test_shaded = 1.0;\n\t\t\t// Step-count shading stays")
source = source.replace("void fragment()", "void main()")
prefix = """#version 300 es
precision highp float;
precision highp int;
const float PI = 3.141592653589793;
in vec2 UV;
out vec4 COLOR;
uniform float test_surface;
uniform float test_stride;
uniform int test_output;
int test_calls = 0;
float test_outside = 0.0;
float test_shaded = 0.0;
"""
# Inject diagnostics at the end of main, after the original fragment logic.
end = source.rfind("}")
source = source[:end] + """
    if (test_output == 1) {
        COLOR = vec4(float(test_calls) / 255.0, test_outside, test_shaded, 1.0);
    } else if (test_output == 2) {
        test_calls = 0;
        test_outside = 0.0;
        float shadow = soft_shadow(0, vec3(0.0), vec3(1.0, 0.0, 0.0),
            vec3(0.0, 1.0, 0.0), test_surface);
        COLOR = vec4(float(test_calls) / 255.0, test_outside, shadow, 1.0);
    }
""" + source[end:]

script = r"""
const results = [];
let failures = 0;
function check(ok, label) {
    results.push((ok ? 'PASS ' : 'FAIL ') + label);
    if (!ok) failures++;
}
try {
    const gl = document.createElement('canvas').getContext('webgl2', {antialias: false});
    check(!!gl, 'WebGL2 available headlessly');
    function compile(type, code) {
        const sh = gl.createShader(type); gl.shaderSource(sh, code); gl.compileShader(sh);
        if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(sh));
        return sh;
    }
    const program = gl.createProgram();
    gl.attachShader(program, compile(gl.VERTEX_SHADER, `#version 300 es
    out vec2 UV;
    void main() {
        vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
        UV = p; gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
    }`));
    gl.attachShader(program, compile(gl.FRAGMENT_SHADER, SHADER));
    gl.linkProgram(program);
    check(gl.getProgramParameter(program, gl.LINK_STATUS), 'actual shader compiles and links: ' + gl.getProgramInfoLog(program));
    gl.useProgram(program);
    gl.viewport(0, 0, 1, 1);
    gl.disable(gl.DITHER);
    const types = {};
    for (let i = 0; i < gl.getProgramParameter(program, gl.ACTIVE_UNIFORMS); i++) {
        const u = gl.getActiveUniform(program, i); types[u.name.replace('[0]', '')] = u.type;
    }
    function set(name, value) {
        const loc = gl.getUniformLocation(program, name);
        if (loc === null) return;
        const type = types[name];
        if (type === gl.INT || type === gl.BOOL || type === gl.SAMPLER_2D) {
            if (Array.isArray(value)) gl.uniform1iv(loc, value); else gl.uniform1i(loc, value);
        } else if (type === gl.FLOAT_VEC3) gl.uniform3fv(loc, value);
        else if (Array.isArray(value)) gl.uniform1fv(loc, value);
        else gl.uniform1f(loc, value);
    }
    Object.entries(DEFAULTS).forEach(([k,v]) => set(k,v));
    Object.entries({shape_count:1, eye:[0,0,0], local_eye:[0,0,0], cam_forward:[1,0,0],
        cam_up:[0,0,1], cam_right:[0,1,0], frame_x:[1,0,0], frame_y:[0,1,0], frame_z:[0,0,1],
        shape_size:[1], box_half:[10], near_dist:1, shape_precision:[0.0001], coarse_steps:96,
        fine_steps:32, shadow_steps:48, color_mode:0, exit_radius:100, fog_tint:[0.2,0.4,0.6],
        test_surface:2, test_stride:0.25, fog_start:0.5}).forEach(([k,v]) => set(k,v));
    function draw(values) {
        Object.entries(values).forEach(([k,v]) => set(k,v));
        gl.drawArrays(gl.TRIANGLES, 0, 3);
        const px = new Uint8Array(4); gl.readPixels(0,0,1,1,gl.RGBA,gl.UNSIGNED_BYTE,px);
        check(gl.getError() === gl.NO_ERROR, 'draw has no GL errors');
        return Array.from(px);
    }
    function rgb(px, want) { return want.every((v,i) => Math.abs(px[i] - Math.round(v*255)) <= 1); }
    let p = draw({test_output:1, fog_distance:0});
    const fullQueries = p[0];
    check(fullQueries > 4 && p[2] === 255, 'fog off reaches and shades the surface');
    p = draw({fog_distance:1});
    check(p[0] < fullQueries && p[1] === 0 && p[2] === 0, 'coarse march saves queries and never queries/shades at or beyond the wall');
    p = draw({coarse_steps:1});
    check(p[0] > 1 && p[1] === 0 && p[2] === 0, 'fine march also stops before the wall');
    p = draw({test_output:0, scatter_density:0.7, fog_clear:0.5, fog_dist:0});
    check(rgb(p, [0.2,0.4,0.6]), 'opaque wall has exact fog colour despite haze');
    p = draw({fog_dist:0.5});
    check(rgb(p, [0.1,0.2,0.3]), 'foreground performance fog eases over the opaque manual wall');
    p = draw({fog_clear:0, fog_color:[0.8,0.1,0.3]});
    check(rgb(p, [0.8,0.1,0.3]), 'nearer opaque performance fog joins the same colour as surfaces at its cutoff');
    const opaqueShed = p;
    p = draw({fog_clear:0.01});
    check(p.slice(0,3).every((v,i)=>Math.abs(v-opaqueShed[i]) < 5), 'first restore frame eases the background instead of popping');
    const earlySky = draw({shape_count:0, fog_distance:2, fog_dist:0.5, fog_clear:0.5,
        exit_radius:1.5, scatter_density:0});
    p = draw({shape_count:1});
    check(rgb(p, earlySky.slice(0,3).map(v=>v/255)), 'finite sky has the same restore colour for early and marched misses');
    set('exit_radius', 100); set('fog_distance', 1);
    p = draw({fog_dist:0, fog_clear:0, view_limit:0.5});
    check(rgb(p, [0,0,0]), 'nearer Kleinian horizon matches the colour of surfaces fading out there');
    set('view_limit', 0);
    p = draw({near_dist:0.5, test_output:1, fog_dist:0, fog_clear:0});
    check(p[0] === 2 && p[1] === 0, 'wall distance follows near_dist on zoom');
    p = draw({near_dist:1, test_surface:1, test_output:1});
    check(p[2] === 0 && p[1] === 0, 'surface exactly on the wall is never shaded or queried');
    p = draw({box_half:[1], local_eye:[-3,0,0]});
    check(p[0] === 0 && p[2] === 0, 'shape entirely beyond the wall needs no distance queries');
    p = draw({box_half:[10], local_eye:[0,0,0], test_surface:0.25, test_stride:0.05,
        test_output:2, coarse_steps:96});
    check(p[0] > 0 && p[1] === 0, 'sideways shadow ray stays inside the camera-centred fog sphere');
    const clippedShadowQueries = p[0];
    p = draw({fog_distance:0});
    check(p[0] > clippedShadowQueries, 'fog wall reduces shadow queries');
    set('test_output', 0); set('scatter_density', 0); set('test_stride', 0.25);
    set('test_surface', 0.25); set('fog_distance', 0);
    const clear = draw({});
    p = draw({fog_distance:1});
    check(rgb(p, clear.slice(0,3).map(v=>v/255)), 'surface before fade start retains its colour');
    p = draw({test_surface:0.75, fog_distance:0});
    const base = p.slice(0,3).map(v=>v/255);
    p = draw({fog_distance:1});
    check(rgb(p, base.map((v,i)=>(v+[0.2,0.4,0.6][i])*0.5)), 'surface halfway through fade smoothly blends into fog');
    // Escape sky is sampled by view direction, even outside and facing away.
    const tex = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE,
        new Uint8Array([80,120,200,255]));
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    const skyColor = [80/255,120/255,200/255];
    p = draw({shape_count:0, eye:[21,0,0], exit_radius:20, fog_distance:0,
        exit_has_skybox:0, exit_sky_alpha:1, fog_dist:0, cam_forward:[1,0,0]});
    check(rgb(p, [0,0,0]), 'sky render gate hides an assigned texture before escape');
    p = draw({exit_has_skybox:1, exit_sky_alpha:0});
    check(rgb(p, [0,0,0]), 'zero sky opacity leaves the original background');
    p = draw({exit_sky_alpha:0.5});
    check(rgb(p, skyColor.map(v=>v*0.5)), 'escaped outward view fades sky halfway');
    p = draw({exit_sky_alpha:1});
    check(rgb(p, skyColor), 'escaped outward view retains the complete sky');
    p = draw({cam_forward:[-1,0,0]});
    check(rgb(p, skyColor), 'sky also surrounds an inward-facing camera');
    p = draw({cam_forward:[1,0,0], fog_distance:1, escape_fog_clear:0.5});
    check(rgb(p, skyColor.map((v,i)=>(v+[0.2,0.4,0.6][i])*0.5)), 'distance fog smoothly reveals the sky');
    p = draw({escape_fog_clear:1, fog_distance:0});
    check(rgb(p, skyColor), 'cleared fog reveals the complete sky without a final colour jump');
    p = draw({shape_count:1, eye:[0,0,0], local_eye:[0,0,0], exit_radius:100,
        test_surface:2, fog_distance:1, escape_fog_clear:0.5, test_output:1});
    check(p[2] === 255, 'fading fog reveals geometry beyond the former opaque wall');
    const almostClear = draw({test_output:0, shape_count:0, eye:[21,0,0],
        cam_forward:[-1,0,0], exit_radius:20, fog_distance:60, escape_fog_clear:0.999,
        scatter_density:0.1, scatter_brightness:0.5, light_color:[1,1,1]});
    p = draw({escape_fog_clear:1, fog_distance:0});
    check(p.slice(0,3).every((v,i)=>Math.abs(v-almostClear[i]) <= 1),
        'early misses have no scattering colour jump when fog finishes clearing');
    const marchedAlmostClear = draw({shape_count:1, eye:[21,0,0], local_eye:[21,0,0],
        frame_x:[-1,0,0], test_surface:1000, box_half:[30], fog_distance:1,
        escape_fog_clear:0.999});
    p = draw({escape_fog_clear:1, fog_distance:0});
    check(p.slice(0,3).every((v,i)=>Math.abs(v-marchedAlmostClear[i]) <= 1),
        'marched misses have no scattering colour jump when fog finishes clearing');
    results.push(failures ? `${failures} FAILED` : 'ALL PASSED');
} catch (e) { results.push('ERROR ' + e.stack); }
document.body.textContent = results.join('\n');
"""
script = "const SHADER = " + json.dumps(prefix + source) + ";\nconst DEFAULTS = " + json.dumps(defaults) + ";\n" + script
scratch = Path(tempfile.mkdtemp(prefix="fractal-fog-render-"))
page = scratch / "test.html"
page.write_text("<!doctype html><body><script>" + script + "</script>")
process = subprocess.Popen([CHROME, "--headless", "--no-first-run", "--no-default-browser-check",
    "--disable-background-networking", "--disable-component-update", "--password-store=basic", "--use-mock-keychain",
    "--disable-gpu", "--enable-unsafe-swiftshader",
    "--user-data-dir=" + str(scratch / "profile"), "--dump-dom", page.as_uri()],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
try:
    stdout, stderr = process.communicate(timeout=15)
except subprocess.TimeoutExpired:
    # Chrome on macOS can keep running after --dump-dom has emitted its result.
    # Terminate only this test's isolated process group, including helpers.
    os.killpg(process.pid, signal.SIGTERM)
    try:
        stdout, stderr = process.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate()
body = re.search(r"<body>(.*?)</body>", stdout, re.S)
output = html.unescape(body[1]) if body else stderr
print(output)
raise SystemExit(0 if output.strip().endswith("ALL PASSED") else 1)
