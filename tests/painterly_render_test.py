#!/usr/bin/env python3
"""Exercise actual painterly shader pixels in headless Chrome WebGL2.

No Python packages required. Set CHROME to override the Chrome executable.
Godot syntax is adapted to GLSL. A low-resolution synthetic colour field
checks stable marks, brush-size response, and preservation of strong edges.
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


source = (ROOT / "src/fractal/painterly.gdshader").read_text()
source = re.sub(r"^(shader_type|render_mode) .*;", "", source, flags=re.M)
source = re.sub(r"(uniform sampler2D \w+)\s*:[^;]+;", r"\1;", source)
source = re.sub(r"(uniform (?:float|vec2) \w+) = [^;]+;", r"\1;", source)
source = source.replace("void fragment()", "void main()")
prefix = """#version 300 es
precision highp float;
in vec2 UV;
out vec4 COLOR;
uniform vec2 TEXTURE_PIXEL_SIZE;
"""
script = r"""
const results = [];
let failures = 0;
function check(ok, label) {
    results.push((ok ? 'PASS ' : 'FAIL ') + label);
    if (!ok) failures++;
}
try {
    const canvas = document.createElement('canvas'); canvas.width = canvas.height = 128;
    const gl = canvas.getContext('webgl2', {antialias: false});
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
    check(gl.getProgramParameter(program, gl.LINK_STATUS), 'actual painterly shader compiles and links');
    gl.useProgram(program); gl.viewport(0,0,128,128); gl.disable(gl.DITHER);
    const texture = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    const data = new Uint8Array(32*32*4);
    for (let y=0; y<32; y++) for (let x=0; x<32; x++) {
        const i=(y*32+x)*4;
        const color=x<16 ? [180,30,20] : [15,160,190];
        for (let c=0;c<3;c++) data[i+c]=color[c]; data[i+3]=255;
    }
    gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,32,32,0,gl.RGBA,gl.UNSIGNED_BYTE,data);
    gl.uniform1i(gl.getUniformLocation(program,'ray_texture'),0);
    gl.uniform2f(gl.getUniformLocation(program,'TEXTURE_PIXEL_SIZE'),1/32,1/32);
    gl.uniform2f(gl.getUniformLocation(program,'display_size'),128,128);
    function draw(size) {
        gl.uniform1f(gl.getUniformLocation(program,'brush_size'),size);
        gl.drawArrays(gl.TRIANGLES,0,3);
        const px=new Uint8Array(128*128*4);
        gl.readPixels(0,0,128,128,gl.RGBA,gl.UNSIGNED_BYTE,px);
        check(gl.getError()===gl.NO_ERROR,'draw has no GL errors'); return px;
    }
    const a=draw(12), b=draw(12), c=draw(24);
    check(a.every((v,i)=>v===b[i]), 'identical source and settings give identical marks across frames');
    check(a.some((v,i)=>Math.abs(v-c[i])>3), 'brush size changes visible stroke structure');
    let stableEdge=true, opaque=true, min=255, max=0;
    for(let y=0;y<128;y++) for(let x=0;x<128;x++) {
        const i=(y*128+x)*4;
        if(x<60) stableEdge &&= a[i]>150 && a[i+1]<45;
        if(x>67) stableEdge &&= a[i]<30 && a[i+1]>135;
        if(x>8 && x<50 && y>8 && y<120) { min=Math.min(min,a[i]);max=Math.max(max,a[i]); }
        opaque &&= a[i+3]===255;
    }
    check(stableEdge,'strong silhouette retains its two colours outside one source texel');
    check(opaque,'presentation fills the image without transparent gaps');
    check(max-min>5 && max-min<35,'flat areas retain bounded visible pigment and paper variation');
    // A horizontal luminance gradient should orient dabs vertically. Remove
    // the underlying linear ramp before comparing directional pigment changes.
    for(let y=0;y<32;y++) for(let x=0;x<32;x++) {
        const i=(y*32+x)*4; data[i]=data[i+1]=data[i+2]=20+x*6;
    }
    gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,32,32,0,gl.RGBA,gl.UNSIGNED_BYTE,data);
    const ramp=draw(24);
    const residual=(x,y)=>ramp[(y*128+x)*4]-(20+((x+0.5)/4-0.5)*6);
    let across=0,along=0;
    for(let y=16;y<108;y++) for(let x=16;x<108;x++) {
        across+=Math.abs(residual(x+4,y)-residual(x,y));
        along+=Math.abs(residual(x,y+4)-residual(x,y));
    }
    check(across>along*1.2,'sampled gradient aligns strokes along its tangent ('+(across/along).toFixed(2)+' directional ratio)');
    results.push(failures ? `${failures} FAILED` : 'ALL PASSED');
} catch(e) { results.push('ERROR '+e.stack); }
document.body.textContent=results.join('\n');
"""
script = "const SHADER = " + json.dumps(prefix + source) + ";\n" + script
scratch = Path(tempfile.mkdtemp(prefix="fractal-painterly-render-"))
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
