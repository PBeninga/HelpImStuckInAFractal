#!/usr/bin/env python3
"""Check production KIFS/bulb bailout math in headless Chrome WebGL2.

Render each distance into four bytes and decode its exact float32 value.
Fixtures have independently derived distances; no estimator math is mocked.
No packages required; set CHROME to override the executable.
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
source = function_body(source, "void fragment()", """
    float d = test_kind == 0 ? kifs_de(0, vec4(test_point, 0.0), test_iters)
                            : mandelbulb_de(0, test_point, test_iters);
    uint bits = floatBitsToUint(d);
    COLOR = vec4(float(bits & 255u), float((bits >> 8u) & 255u),
                 float((bits >> 16u) & 255u), float((bits >> 24u) & 255u)) / 255.0;
""")
source = source.replace("void fragment()", "void main()")
prefix = """#version 300 es
precision highp float;
precision highp int;
const float PI = 3.141592653589793;
in vec2 UV;
out vec4 COLOR;
uniform vec3 test_point;
uniform int test_kind;
uniform int test_iters;
"""
script = r"""
const results = [];
let failures = 0;
function check(ok, label) {
    results.push((ok ? 'PASS ' : 'FAIL ') + label);
    if (!ok) failures++;
}
try {
    const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1;
    const gl = canvas.getContext('webgl2', {antialias:false, premultipliedAlpha:false});
    if (!gl) throw new Error('WebGL2 unavailable');
    function compile(type, code) {
        const sh=gl.createShader(type); gl.shaderSource(sh,code); gl.compileShader(sh);
        if (!gl.getShaderParameter(sh,gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(sh));
        return sh;
    }
    const program=gl.createProgram();
    gl.attachShader(program,compile(gl.VERTEX_SHADER,`#version 300 es
    out vec2 UV;
    void main() {
        vec2 p=vec2(float((gl_VertexID<<1)&2),float(gl_VertexID&2));
        UV=p; gl_Position=vec4(p*2.0-1.0,0.0,1.0);
    }`));
    gl.attachShader(program,compile(gl.FRAGMENT_SHADER,SHADER));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program,gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program));
    gl.useProgram(program); gl.viewport(0,0,1,1); gl.disable(gl.DITHER);
    const types={};
    for(let i=0;i<gl.getProgramParameter(program,gl.ACTIVE_UNIFORMS);i++) {
        const u=gl.getActiveUniform(program,i); types[u.name.replace('[0]','')]=u.type;
    }
    function set(name,value) {
        const loc=gl.getUniformLocation(program,name);
        if(loc===null) return;
        if(types[name]===gl.INT || types[name]===gl.BOOL) {
            if(Array.isArray(value)) gl.uniform1iv(loc,value); else gl.uniform1i(loc,value);
        } else if(types[name]===gl.FLOAT_VEC3) gl.uniform3fv(loc,value);
        else if(Array.isArray(value)) gl.uniform1fv(loc,value);
        else gl.uniform1f(loc,value);
    }
    Object.entries(DEFAULTS).forEach(([k,v])=>set(k,v));
    function draw(values) {
        Object.entries(values).forEach(([k,v])=>set(k,v));
        gl.drawArrays(gl.TRIANGLES,0,3);
        const bytes=new Uint8Array(4); gl.readPixels(0,0,1,1,gl.RGBA,gl.UNSIGNED_BYTE,bytes);
        if(gl.getError()!==gl.NO_ERROR) throw new Error('GL draw failed');
        return new DataView(bytes.buffer).getFloat32(0,true);
    }
    function expect(values,want,label,tolerance=2e-5) {
        const got=draw(values);
        check(Number.isFinite(got) && Math.abs(got-want)<=tolerance*Math.max(Math.abs(want),1e-3),
              label+' (want '+want+', got '+got+')');
    }
    Object.entries({test_kind:0,test_iters:8,test_point:[3,3,3],kifs_scale:[3],kifs_fold:[1],
        kifs_offset_0:[1],kifs_offset_1:[1],kifs_offset_2:[1],kifs_offset_3:[0]}).forEach(([k,v])=>set(k,v));
    expect({kifs_bailout_radius_squared:1e6},3.4664775421714564,'KIFS 1x preserves n=6 escape');
    expect({kifs_bailout_radius_squared:256e6},3.464365607030388,'KIFS 16x continues to n=8');
    expect({test_iters:1},Math.sqrt(3)*7/3,'KIFS iteration cap wins');
    expect({test_kind:1,test_iters:8,test_point:[3,0,0],mandelbulb_power:[2],mandelbulb_bailout_margin:1},
        1.5*Math.log(3),'bulb 1x stops immediately');
    expect({mandelbulb_bailout_margin:4},1.5246050995173255,'bulb 4x includes the next iteration',1e-4);
    expect({test_iters:0},1.5*Math.log(3),'bulb zero iterations does not take a final escape step');
    // Julia c=0 has the exact radial estimate 0.5*r*ln(r), for every power.
    // Use the positive z axis (zero angles) to isolate radial arithmetic from
    // SwiftShader's approximate trigonometry. Expanded thresholds must not
    // overflow either r^n or the derivative.
    set('mandelbulb_julia',[1]); set('test_iters',32);
    for(const power of [1.5,2,8,16,32]) for(const margin of [1,4,16]) {
        for(const radius of [1.11,3,16]) {
            expect({test_point:[0,0,radius],mandelbulb_power:[power],mandelbulb_bailout_margin:margin},
                .5*radius*Math.log(radius),`Julia power ${power}, margin ${margin}, radius ${radius}`);
        }
    }
    results.push(failures ? `${failures} FAILED` : 'ALL PASSED');
} catch(e) { results.push('ERROR '+e.stack); }
document.body.textContent=results.join('\n');
"""
script = "const SHADER = " + json.dumps(prefix + source) + ";\nconst DEFAULTS = " + json.dumps(defaults) + ";\n" + script
scratch = Path(tempfile.mkdtemp(prefix="fractal-bailout-render-"))
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
