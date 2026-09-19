# -*- coding: utf-8 -*-
"""青记 App 图标生成器 —— 矢量绘制 + 超采样抗锯齿，导出 Android 各密度与自适应图标前景。
风格：青绿渐变圆角方块 + 白色打开书本 + 深青描边 + 青色对勾（参考 grok_1789798275854.jpg）。
"""
import os
from PIL import Image, ImageDraw

# ---------- 主题色 ----------
BG_TOP = (54, 201, 186)     # #36C9BA 左上
BG_BOT = (21, 167, 154)     # #15A79A 右下
INK = (13, 98, 93)          # #0D625D 深青（描边/封面/书脊）
PAGE = (255, 255, 255)      # 白色书页
CHECK = (35, 180, 166)      # #23B4A6 对勾

ROOT = r"D:\Agent project\daka\app"
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")
ASSET_DIR = os.path.join(ROOT, "assets", "icon")


def bez(p0, p1, p2, p3, n=44):
    pts = []
    for i in range(n + 1):
        t = i / n
        mt = 1 - t
        x = (mt**3) * p0[0] + 3 * (mt**2) * t * p1[0] + 3 * mt * (t**2) * p2[0] + (t**3) * p3[0]
        y = (mt**3) * p0[1] + 3 * (mt**2) * t * p1[1] + 3 * mt * (t**2) * p2[1] + (t**3) * p3[1]
        pts.append((x, y))
    return pts


# 书本轮廓（归一化：书宽=1，原点在书中心，x 向右，y 向下）
SEGS = [
    ((-0.5, -0.325), (-0.40, -0.365), (-0.30, -0.375), (-0.20, -0.372)),
    ((-0.20, -0.372), (-0.12, -0.370), (-0.05, -0.350), (0.0, -0.342)),
    ((0.0, -0.342), (0.05, -0.350), (0.12, -0.370), (0.20, -0.372)),
    ((0.20, -0.372), (0.30, -0.375), (0.40, -0.365), (0.5, -0.325)),
    ((0.5, -0.325), (0.515, -0.10), (0.515, 0.12), (0.5, 0.295)),
    ((0.5, 0.295), (0.30, 0.345), (0.14, 0.372), (0.0, 0.372)),
    ((0.0, 0.372), (-0.14, 0.372), (-0.30, 0.345), (-0.5, 0.295)),
    ((-0.5, 0.295), (-0.515, 0.12), (-0.515, -0.10), (-0.5, -0.325)),
]


def book_points(bookW, ss):
    """返回书本轮廓在 SS 像素空间中的闭合点（中心在原点）。"""
    pts = []
    for s in SEGS:
        p = bez(s[0], s[1], s[2], s[3])
        pts.extend(p if not pts else p[1:])
    return [(x * bookW, y * bookW) for (x, y) in pts]


def draw_book(draw, cx, cy, bookW):
    """在 (cx,cy) 中心以书宽 bookW 绘制书本（含封面阴影、白页、描边、书脊、对勾）。"""
    pts = book_points(bookW, 1)
    def T(offset_y=0.0, scale=1.0):
        return [(cx + x * scale, cy + y * scale + offset_y) for (x, y) in pts]

    # 封面（下移一点露出深青边缘）
    draw.polygon(T(offset_y=0.024 * bookW), fill=INK)
    # 白色书页
    draw.polygon(T(), fill=PAGE)
    # 描边
    stroke = max(1, int(round(0.020 * bookW)))
    outline = T()
    draw.line(outline + [outline[0]], fill=INK, width=stroke, joint="curve")

    # 书脊（中央竖线）
    spine_w = max(1, int(round(0.020 * bookW)))
    draw.line([(cx, cy - 0.342 * bookW), (cx, cy + 0.372 * bookW)], fill=INK, width=spine_w)

    # 对勾（右页）
    cw = max(1, int(round(0.052 * bookW)))
    p1 = (cx + 0.070 * bookW, cy + 0.078 * bookW)
    p2 = (cx + 0.150 * bookW, cy + 0.160 * bookW)
    p3 = (cx + 0.300 * bookW, cy - 0.020 * bookW)
    for a, b in ((p1, p2), (p2, p3)):
        draw.line([a, b], fill=CHECK, width=cw, joint="curve")
    r = cw / 2.0
    for (px, py) in (p1, p2, p3):
        draw.ellipse([px - r, py - r, px + r, py + r], fill=CHECK)


def gradient(size):
    small = 256
    g = Image.new("RGB", (small, small))
    px = g.load()
    for y in range(small):
        for x in range(small):
            t = (x + y) / (2.0 * (small - 1))
            px[x, y] = (
                int(BG_TOP[0] + (BG_BOT[0] - BG_TOP[0]) * t),
                int(BG_TOP[1] + (BG_BOT[1] - BG_TOP[1]) * t),
                int(BG_TOP[2] + (BG_BOT[2] - BG_TOP[2]) * t),
            )
    return g.resize((size, size), Image.BICUBIC)


def ss_factor(size):
    return min(8, max(2, 2048 // size))


def render_icon(size, book_ratio=0.50, bg=True):
    ss = ss_factor(size)
    S = size * ss
    base = gradient(S).convert("RGBA")
    if bg:
        radius = int(round(0.225 * S))
        mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=radius, fill=255)
        base.putalpha(mask)
    draw = ImageDraw.Draw(base)
    draw_book(draw, S / 2.0, S / 2.0, book_ratio * S)
    return base.resize((size, size), Image.LANCZOS)


def render_foreground(size, book_ratio=0.48):
    ss = ss_factor(size)
    S = size * ss
    base = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(base)
    draw_book(draw, S / 2.0, S / 2.0, book_ratio * S)
    return base.resize((size, size), Image.LANCZOS)


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG")
    print("  ->", os.path.relpath(path, ROOT))


DENSITIES = {
    "mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192,
}
FG_SIZES = {
    "mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432,
}

print("生成 legacy ic_launcher.png ...")
for d, s in DENSITIES.items():
    save(render_icon(s), os.path.join(RES, f"mipmap-{d}", "ic_launcher.png"))

print("生成自适应前景 ic_launcher_foreground.png ...")
for d, s in FG_SIZES.items():
    save(render_foreground(s), os.path.join(RES, f"mipmap-{d}", "ic_launcher_foreground.png"))

print("生成应用内/展示用 app_icon ...")
os.makedirs(ASSET_DIR, exist_ok=True)
save(render_icon(1024), os.path.join(ASSET_DIR, "app_icon.png"))
save(render_icon(512), os.path.join(ASSET_DIR, "app_icon_512.png"))
save(render_icon(1024, bg=False, book_ratio=0.62), os.path.join(ASSET_DIR, "app_icon_mark.png"))

print("完成。")
