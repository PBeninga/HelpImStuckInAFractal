#!/usr/bin/env python3
"""Render the production phosphor presentation shader using headless WebGL2.

Also exercise retained-target alpha decay and opaque strip replacement. This
checks GPU blending/shader output; Godot's target scheduling is covered by the
GDScript test and still needs visual verification in a windowed Godot run.
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
CHROME = os.environ.get("CHROME") or shutil.which("google-chrome") or shutil.which("chromium") or "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
source = (ROOT / "src/fractal/phosphor_display.gdshader").read_text()
source = re.sub(r"^(shader_type|render_mode).*;", "", source, flags=re.M)
source = re.sub(r"(uniform float \w+) = [^;]+;", r"\1;", source)
source = source.replace("void fragment()", "void main()")
prefix = """#version 300 es
precision highp float;
in vec2 UV;
out vec4 COLOR;
uniform sampler2D TEXTURE;
uniform vec2 TEXTURE_PIXEL_SIZE;
"""
script = "const SOURCE = " + json.dumps(prefix + source) + ";\n" + r"""
const results = []; let failures = 0;
function check(ok, label) { results.push((ok ? 'PASS ' : 'FAIL ') + label); if (!ok) failures++; }
try {
 const gl = document.createElement('canvas').getContext('webgl2', {antialias:false});
 if (!gl) throw new Error('WebGL2 unavailable');
 function shader(type, text) {
  const s = gl.createShader(type); gl.shaderSource(s,text); gl.compileShader(s);
  if (!gl.getShaderParameter(s,gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s)); return s;
 }
 function program(fragment) {
  const p = gl.createProgram();
  gl.attachShader(p,shader(gl.VERTEX_SHADER,`#version 300 es
  in vec2 pos; out vec2 UV; void main(){UV=pos*0.5+0.5;gl_Position=vec4(pos,0,1);}`));
  gl.attachShader(p,shader(gl.FRAGMENT_SHADER,fragment));gl.linkProgram(p);
  if (!gl.getProgramParameter(p,gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
  gl.useProgram(p);const loc=gl.getAttribLocation(p,'pos');gl.enableVertexAttribArray(loc);
  gl.vertexAttribPointer(loc,2,gl.FLOAT,false,0,0); return p;
 }
 const b=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,b);
 gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,1,-1,-1,1,-1,1,1,-1,1,1]),gl.STATIC_DRAW);
 function texture(data) {
  const t=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,t);
  gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA8,16,16,0,gl.RGBA,gl.UNSIGNED_BYTE,data);
  for(const pname of [gl.TEXTURE_MIN_FILTER,gl.TEXTURE_MAG_FILTER])gl.texParameteri(gl.TEXTURE_2D,pname,gl.NEAREST);
  for(const pname of [gl.TEXTURE_WRAP_S,gl.TEXTURE_WRAP_T])gl.texParameteri(gl.TEXTURE_2D,pname,gl.CLAMP_TO_EDGE);return t;
 }
 const target=texture(null),fb=gl.createFramebuffer();gl.bindFramebuffer(gl.FRAMEBUFFER,fb);
 gl.framebufferTexture2D(gl.FRAMEBUFFER,gl.COLOR_ATTACHMENT0,gl.TEXTURE_2D,target,0);
 gl.viewport(0,0,16,16);
 const solid=program(`#version 300 es
 precision highp float; uniform vec4 value;out vec4 COLOR;void main(){COLOR=value;}`);
 function paint(r,g,b,a){gl.uniform4f(gl.getUniformLocation(solid,'value'),r,g,b,a);gl.drawArrays(gl.TRIANGLES,0,6);}
 function pixel(x,y){const p=new Uint8Array(4);gl.readPixels(x,y,1,1,gl.RGBA,gl.UNSIGNED_BYTE,p);return p;}
 gl.disable(gl.BLEND);paint(1,0,0,1);
 gl.enable(gl.BLEND);gl.blendFunc(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA);paint(0,0,0,0.5);
 gl.enable(gl.SCISSOR_TEST);gl.scissor(0,8,16,2);paint(0,1,0,1);gl.disable(gl.SCISSOR_TEST);
 check(Math.abs(pixel(4,2)[0]-128)<=1,'unrefreshed rows retain decayed history');
 check(pixel(4,8)[1]===255 && pixel(4,8)[0]===0,'new strip replaces stale pixels opaquely');
 gl.disable(gl.BLEND);
 const data=new Uint8Array(16*16*4);
 for(let i=0;i<256;i++)data[i*4+3]=255;
 for(let y=0;y<16;y++){let i=(y*16+8)*4;data[i]=data[i+1]=data[i+2]=100;}
 texture(data);
 const display=program(SOURCE);
 function set(name,v){gl.uniform1f(gl.getUniformLocation(display,name),v);}
 gl.uniform2f(gl.getUniformLocation(display,'TEXTURE_PIXEL_SIZE'),1/16,1/16);
 set('output_height',16);set('scan_center',0.5);set('scan_width',0.125);set('glow',0);
 gl.drawArrays(gl.TRIANGLES,0,6);const noGlow=pixel(6,2),base=pixel(8,2),beam=pixel(1,8),dark=pixel(1,1);
 check(base[1]>base[0],'phosphor presentation tints reconstructed image cyan');
 check(beam[1]>dark[1],'scan band marks the refreshed region');
 set('glow',1);gl.drawArrays(gl.TRIANGLES,0,6);const glow=pixel(6,2);
 check(glow[1]>noGlow[1],'glow spreads brightness into neighboring pixels');
 check(gl.getError()===gl.NO_ERROR,'render completes without WebGL errors');
 results.push(failures ? `${failures} FAILED` : 'ALL PASSED');
} catch(e) {results.push('ERROR '+e.stack);}
document.body.textContent=results.join('\n');
"""
scratch = Path(tempfile.mkdtemp(prefix="fractal-phosphor-render-"))
page = scratch / "test.html"
page.write_text("<!doctype html><body><script>" + script + "</script>")
process = subprocess.Popen([CHROME, "--headless", "--no-first-run", "--no-default-browser-check",
    "--disable-background-networking", "--disable-component-update", "--password-store=basic", "--use-mock-keychain",
    "--disable-gpu", "--enable-unsafe-swiftshader", "--user-data-dir=" + str(scratch / "profile"), "--dump-dom", page.as_uri()],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
try:
    stdout, stderr = process.communicate(timeout=15)
except subprocess.TimeoutExpired:
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
