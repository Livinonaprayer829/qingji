# -*- coding: utf-8 -*-
"""开屏动画预览渲染器（与 Flutter 端一致）：
   - splash_preview.gif  动画
   - splash_frames.png   关键帧拼图
   仅设计验证用,不参与打包。
"""
import math
from PIL import Image, ImageDraw, ImageFont

W, H = 320, 568
ICON = 220
ICON_CX, ICON_CY = W // 2, 268
TAG_Y = ICON_CY + ICON // 2 + 24
FONT = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 15)
TOTAL = 2.00
FADE = 0.42
FPS = 20

G1, G2 = (60, 203, 188), (21, 167, 154)
INK = (13, 98, 93)
CHK = (35, 180, 166)

def clamp(v, a=0.0, b=1.0): return max(a, min(b, v))
def ease_out(t): t = clamp(t); return 1 - (1 - t) ** 2
def ease_out_cubic(t): t = clamp(t); return 1 - (1 - t) ** 3
c1_ = 1.70158; c3_ = c1_ + 1
def ease_out_back(t): t = clamp(t); return 1 + c3_ * (t - 1) ** 3 + c1_ * (t - 1) ** 2
def ease_in_out_cubic(t):
    t = clamp(t); return 4 * t ** 3 if t < 0.5 else 1 - (-2 * t + 2) ** 3 / 2

def interval(t, a, b, ease):
    if t <= a: return 0.0
    if t >= b: return 1.0
    return ease((t - a) / (b - a))

# ---- 路径结构:起点 + 4 段三次贝塞尔(c1,c2,end),归一化坐标 ----
pR0 = (0, -0.342)
pR = [[(0.05, -0.350), (0.12, -0.370), (0.20, -0.372)],
      [(0.30, -0.375), (0.40, -0.365), (0.5, -0.325)],
      [(0.515, -0.10), (0.515, 0.12), (0.5, 0.295)],
      [(0.30, 0.345), (0.14, 0.372), (0.0, 0.372)]]
pL0 = (0, -0.342)
pL = [[(-0.05, -0.350), (-0.12, -0.370), (-0.20, -0.372)],
      [(-0.30, -0.375), (-0.40, -0.365), (-0.5, -0.325)],
      [(-0.515, -0.10), (-0.515, 0.12), (-0.5, 0.295)],
      [(-0.30, 0.345), (-0.14, 0.372), (0.0, 0.372)]]
cR0 = (0, -0.366)
cR = [[(0.17, -0.366), (0.33, -0.366), (0.5, -0.366)],
      [(0.5, -0.122), (0.5, 0.122), (0.5, 0.366)],
      [(0.33, 0.366), (0.17, 0.366), (0.0, 0.366)],
      [(0.0, 0.122), (0.0, -0.122), (0.0, -0.366)]]
cL0 = (0, -0.366)
cL = [[(-0.17, -0.366), (-0.33, -0.366), (-0.5, -0.366)],
      [(-0.5, -0.122), (-0.5, 0.122), (-0.5, 0.366)],
      [(-0.33, 0.366), (-0.17, 0.366), (0.0, 0.366)],
      [(0.0, 0.122), (0.0, -0.122), (0.0, -0.366)]]

def cubic(p0, c1, c2, p3, n=28):
    o = []
    for i in range(n + 1):
        t = i / n; mt = 1 - t
        o.append((mt**3*p0[0] + 3*mt*mt*t*c1[0] + 3*mt*t*t*c2[0] + t**3*p3[0],
                  mt**3*p0[1] + 3*mt*mt*t*c1[1] + 3*mt*t*t*c2[1] + t**3*p3[1]))
    return o

def lerp_pts(a0, a, b0, b, m, w):
    def L(p, q): return ((p[0] + (q[0]-p[0])*m)*w, (p[1] + (q[1]-p[1])*m)*w)
    pts = [L(a0, b0)]
    for i in range(4):
        seg = cubic(L(a[i][0], b[i][0]), L(a[i][1], b[i][1]),
                    L(a[i][2], b[i][2]), L(a[i][2], b[i][2]))
        # 需要 end 作为 p3,这里手动构造
        seg = cubic(L(a[i][0], b[i][0]), L(a[i][1], b[i][1]),
                    L(a[i][2], b[i][2]), L(a[i][2], b[i][2]))
        pts.extend(seg[1:])
    return pts

def lerp_path(a0, a, b0, b, m, w):
    def L(p, q): return ((p[0] + (q[0]-p[0])*m)*w, (p[1] + (q[1]-p[1])*m)*w)
    P0 = L(a0, b0)
    pts = [P0]
    for i in range(4):
        cA = L(a[i][0], b[i][0]); cB = L(a[i][1], b[i][1]); E = L(a[i][2], b[i][2])
        seg = cubic(P0, cA, cB, E)
        pts.extend(seg[1:])
        P0 = E
    return pts

def thick(d, pts, width, color):
    for a, b in zip(pts[:-1], pts[1:]):
        d.line([a, b], fill=color, width=width, joint="curve")
    r = width / 2.0
    for (x, y) in [pts[0], pts[-1]]:
        d.ellipse([x-r, y-r, x+r, y+r], fill=color)

def render_icon_layer(closeT, scale):
    L = ICON
    w = L * 0.58
    layer = Image.new("RGBA", (L, L), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx = cy = L / 2

    flipT = ease_in_out_cubic(clamp(closeT / 0.65))
    m = flipT   # 收方与翻页全程同步,避免"某一刻突变"
    sx = 1 - 2 * flipT
    gx = -0.25 * w * flipT
    cx += gx

    white = (255, 255, 255, 255)
    inkA = INK + (255,)
    sw = max(1, round(0.020 * w))

    rpath = [(cx + x, cy + y) for x, y in lerp_path(pR0, pR, cR0, cR, m, w)]

    # 封面厚度
    if m > 0.01:
        d.polygon([(x, y + 0.022 * w) for x, y in rpath],
                  fill=INK + (int(255 * m),))
    # 右页
    d.polygon(rpath, fill=white)
    # 对勾
    p1 = (cx + 0.070*w, cy + 0.078*w); p2 = (cx + 0.150*w, cy + 0.160*w); p3 = (cx + 0.300*w, cy - 0.020*w)
    thick(d, [p1, p2, p3], max(1, round(0.052 * w)), CHK + (255,))
    # 右页描边
    d.line(rpath + [rpath[0]], fill=inkA, width=sw, joint="curve")
    # 书脊
    spineO = 1 - flipT
    if spineO > 0.01:
        d.line([(cx, cy - 0.342*w), (cx, cy + 0.372*w)],
               fill=INK + (int(255*spineO),), width=sw)
    # 左页
    if abs(sx) > 0.002:
        lpath = [(cx + x*sx, cy + y) for x, y in lerp_path(pL0, pL, cL0, cL, m, w)]
        d.polygon(lpath, fill=white)
        shade = math.sin(math.pi * flipT) * 0.16
        if shade > 0.01:
            d.polygon(lpath, fill=(0, 0, 0, int(255*shade)))
        d.line(lpath + [lpath[0]], fill=inkA, width=sw, joint="curve")
    # 书脊折痕
    if m > 0.01:
        d.line([(cx + 0.055*w, cy - 0.30*w), (cx + 0.055*w, cy + 0.33*w)],
               fill=INK + (int(255*m),), width=max(1, round(0.014*w)))

    if abs(scale - 1.0) > 0.001:
        ns = max(2, int(round(L * scale)))
        layer = layer.resize((ns, ns), Image.LANCZOS)
    return layer

def render_frame(t):
    img = BG.copy()
    d = ImageDraw.Draw(img)
    iconO = interval(t, 0.0, 0.21*TOTAL, ease_out)
    iconScale = 0.9 + 0.1 * interval(t, 0.0, 0.23*TOTAL, ease_out_back)
    ta, tb = 0.82*TOTAL, 0.95*TOTAL
    if t <= ta or t >= tb:
        settle = 1.0
    else:
        k = (t - ta) / (tb - ta)
        settle = 1 - 0.03*ease_out(k/0.45) if k < 0.45 else 0.97 + 0.03*ease_out_back((k-0.45)/0.55)
    closeT = clamp((t - 0.36*TOTAL) / (0.50*TOTAL))

    layer = render_icon_layer(closeT, iconScale*settle)
    if iconO < 0.999:
        layer.putalpha(layer.getchannel("A").point(lambda v: int(v*iconO)))
    img.alpha_composite(layer, (ICON_CX - layer.width//2, ICON_CY - layer.height//2))

    textO = interval(t, 0.17*TOTAL, 0.36*TOTAL, ease_out)
    slide = 14*(1 - interval(t, 0.17*TOTAL, 0.38*TOTAL, ease_out_cubic))
    spacing = 1 + 4*interval(t, 0.17*TOTAL, 0.44*TOTAL, ease_out)
    if textO > 0.01:
        text = "青记·简约清爽"
        ws = [d.textlength(c, font=FONT) for c in text]
        tw = sum(ws) + spacing*(len(text)-1)
        x = (W - tw)/2; y = TAG_Y + slide
        for c, cw in zip(text, ws):
            d.text((x+1, y+1), c, font=FONT, fill=(0, 0, 0, int(60*textO)))
            d.text((x, y), c, font=FONT, fill=(255, 255, 255, int(255*textO)))
            x += cw + spacing
    if t > TOTAL:
        img = Image.blend(img, LIGHT, clamp((t-TOTAL)/FADE))
    return img

BG = Image.new("RGBA", (W, H)); _px = BG.load()
for y in range(H):
    for x in range(W):
        k = (x + y)/(W + H - 2)
        _px[x, y] = (int(G1[0]+(G2[0]-G1[0])*k), int(G1[1]+(G2[1]-G1[1])*k),
                     int(G1[2]+(G2[2]-G1[2])*k), 255)
LIGHT = Image.new("RGBA", (W, H), (234, 244, 242, 255))

frames = []
for i in range(int((TOTAL+FADE)*FPS)+1):
    frames.append(render_frame(i/FPS).convert("P", palette=Image.ADAPTIVE))
frames[0].save(r"D:\Agent project\daka\app\tool\splash_preview.gif", save_all=True,
               append_images=frames[1:], duration=int(1000/FPS), loop=0, optimize=False)
print("GIF frames:", len(frames))

keys = [0.75, 1.05, 1.18, 1.30, 1.45, 1.85]
strip = Image.new("RGBA", (W*len(keys), H), (255, 255, 255, 255))
for i, t in enumerate(keys):
    strip.alpha_composite(render_frame(t), (i*W, 0))
strip.convert("RGB").save(r"D:\Agent project\daka\app\tool\splash_frames.png")
print("filmstrip:", keys)
