import math
from ball import build

# The mod's own palette (main.lua BALL_COLORS), with the outline lifted from
# #171717 to #272c27: in game the sprite sits on the bright playfield, where
# near-black is the right edge; on a near-black card it dissolves instead.
COLORS = {1:"#272c27", 2:"#d94038", 3:"#f7f7f7"}
N, S = 16, 34
grid = build(N)

SIZE = N * S
rects = "".join(
    f'<rect x="{x*S}" y="{y*S}" width="{S}" height="{S}" fill="{COLORS[v]}"/>'
    for y, row in enumerate(grid) for x, v in enumerate(row) if v)
ball = (f'<svg width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}" '
        f'shape-rendering="crispEdges" xmlns="http://www.w3.org/2000/svg">{rects}</svg>')

html = f"""<!doctype html><meta charset="utf-8"><style>
  * {{ margin:0; padding:0; box-sizing:border-box; }}
  html,body {{ width:1920px; height:1080px; overflow:hidden; }}
  body {{
    background:#0b0d0c; font-family:"Unifont", monospace;
    display:flex; align-items:center; justify-content:center; position:relative;
  }}
  .glow {{ position:absolute; inset:0; background:
    radial-gradient(46% 60% at 27% 50%, rgba(217,64,56,.16) 0%, rgba(217,64,56,0) 70%),
    radial-gradient(70% 84% at 30% 50%, #161c17 0%, #0b0d0c 74%); }}
  .lines {{ position:absolute; inset:0; background:repeating-linear-gradient(
      to bottom, rgba(255,255,255,.022) 0 2px, transparent 2px 5px); }}
  .row {{ position:relative; display:flex; align-items:center; gap:120px; }}
  .mark {{ display:block; filter:drop-shadow(0 22px 44px rgba(0,0,0,.65)); }}
  .type {{ display:flex; flex-direction:column; }}
  .gen1 {{ font-size:100px; line-height:1.05; color:#d94038; letter-spacing:17px; }}
  .auto {{ font-size:170px; line-height:1.05; color:#f7f7f7; letter-spacing:4px; }}
  .rule {{ height:9px; width:200px; background:#9bbc0f; margin:36px 0 24px; }}
  .sub {{ font-size:42px; line-height:1; color:#8b978f; letter-spacing:4px; }}
</style>
<div class="glow"></div><div class="lines"></div>
<div class="row">
  <div class="mark">{ball}</div>
  <div class="type">
    <div class="gen1">GEN1</div>
    <div class="auto">AUTOSAVE</div>
    <div class="rule"></div>
    <div class="sub">a mod for gen1recomp</div>
  </div>
</div>"""
open("logo.html", "w").write(html)
print("ok")
