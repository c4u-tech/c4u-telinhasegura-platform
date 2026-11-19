"""Builds the Telinha Segura brand set from one geometry, and writes every
copy the app, its web build and the site ship.

    python brand/source/build_brand.py [root]

root defaults to the repository this file lives in; give another directory
to write a fresh tree there and diff it against the committed one. Needs
Python with fonttools, uharfbuzz, cairosvg (and the cairo library; on macOS
with Homebrew, run with DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib) and
pillow. The wordmark is outlined from the app's bundled variable font,
app/assets/fonts/BricolageGrotesque.ttf, instanced at wght 800, opsz 96,
wdth 100 (the endorsement at wght 500, opsz 14).

It writes, under root:
- brand/svg, brand/png, brand/tokens: the mascot in three tiers (mark,
  simplified, mini), the wordmark and the horizontal, stacked and endorsed
  signatures, each in four variants; the mascot looking back, the perched
  one-colour figure and one row of the brand pattern, for the site; the
  e-mail PNGs and the design tokens;
- brand/app-icon: the app icon (the mascot on an ink tile, and its dark
  variant), the Android adaptive layers and monochrome, and the native
  splash marks; flutter_launcher_icons and flutter_native_splash read these
  PNGs (see app/*.yaml);
- brand/favicon: the mini mascot favicon (16, 32, 48 px) and the web icons;
- the copies listed in COPIES, byte for byte;
- brand/manifest.sha256: the hash of every file above. tools/brandcheck
  fails when a committed file no longer matches it, so a copy edited by
  hand, or a master changed without running this script, is caught.
"""
import hashlib, io, json, math, os, re, shutil, sys
import uharfbuzz as hb, cairosvg
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
sys.dont_write_bytecode = True  # the helper import must not leave a cache folder in the tree
from contrast import cr, oklch

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
ROOT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else REPO
OUT = os.path.join(ROOT, 'brand')
FONT_SRC = os.path.join(REPO, 'app', 'assets', 'fonts', 'BricolageGrotesque.ttf')
WRITTEN = []  # repository-relative paths of every file written

C = dict(cream='#FBF6EC', dark='#0F2A30', ink='#1E5B66', sun='#FFC42E', beak='#FF5A36', sky='#A9DDE8', white='#FFFFFF')

def n(v):
    """A coordinate to at most three decimals, trailing zeros dropped, so
    the output is the same on every run and every machine."""
    s = f'{v:.3f}'.rstrip('0').rstrip('.')
    return '0' if s == '-0' else s
def n5(v):
    """A scale factor to five decimals, so a ratio such as 58/64 is written exactly."""
    return f'{v:.5f}'.rstrip('0').rstrip('.')
def pts(*ps):
    return ' '.join(f'{n(x)} {n(y)}' for x, y in ps)

# ---------------- the mascot (a 132-unit box, the figure in 0..120) ----------------
FIG = 132
FIG_ORIGIN = -6
FIG_BBOX = (3.7, 20.0, 115.03, 103.4)   # tail's back to beak tip, crown to feet
SMALL_BBOX = (14.0, 20.0, 115.03, 90.0)  # the tiers without tail and legs

def rrect(x, y, w, h, r):
    return (f'M{n(x+r)} {n(y)}H{n(x+w-r)}A{n(r)} {n(r)} 0 0 1 {n(x+w)} {n(y+r)}V{n(y+h-r)}A{n(r)} {n(r)} 0 0 1 {n(x+w-r)} {n(y+h)}'
            f'H{n(x+r)}A{n(r)} {n(r)} 0 0 1 {n(x)} {n(y+h-r)}V{n(y+r)}A{n(r)} {n(r)} 0 0 1 {n(x+r)} {n(y)}Z')
def circle_path(cx, cy, r):
    return f'M{n(cx+r)} {n(cy)}A{n(r)} {n(r)} 0 1 0 {n(cx-r)} {n(cy)}A{n(r)} {n(r)} 0 1 0 {n(cx+r)} {n(cy)}Z'

def offset_edges(c, r):
    """Each edge of a polygon, clockwise on screen, moved outward by r."""
    out = []
    for (x0, y0), (x1, y1) in zip(c, c[1:] + c[:1]):
        L = math.hypot(x1 - x0, y1 - y0); nx, ny = (y1 - y0) / L * r, -(x1 - x0) / L * r
        out.append(((x0 + nx, y0 + ny), (x1 + nx, y1 + ny)))
    return out
def rounded_triangle(c, r):
    """The outline of a triangle whose corners are arcs of radius r around
    the points of c (clockwise on screen)."""
    e = offset_edges(c, r); d = f'M{pts(e[0][0])}'
    for i, (_, b) in enumerate(e):
        d += f'L{pts(b)}A{n(r)} {n(r)} 0 0 1 {pts(e[(i + 1) % 3][0])}'
    return d + 'Z'
def y_at(edge, x):
    (x0, y0), (x1, y1) = edge
    return y0 + (y1 - y0) * (x - x0) / (x1 - x0)

# The body is a rounded rectangle; the head's bands are slices of it, cut
# by straight chords in the path data rather than by a clip-path, which some
# icon tools ignore.
BX, BY, BW, BH, BR = 14, 20, 84, 70, 26
BODY = rrect(BX, BY, BW, BH, BR)
ARC = f'A{BR} {BR} 0 0 1'
def chord(y):
    """Where a height in the upper corners meets the body's left and right edges."""
    d = math.sqrt(BR * BR - (BY + BR - y) ** 2)
    return n(BX + BR - d), n(BX + BW - BR + d)
CROWN_Y, BROW_Y = 38, 44.5
(cl, cr_), (bl, br) = chord(CROWN_Y), chord(BROW_Y)
CROWN = f'M{cl} {CROWN_Y}{ARC} 40 20H72{ARC} {cr_} {CROWN_Y}Z'
EYEBROW = f'M{cl} {CROWN_Y}H{cr_}{ARC} {br} {n(BROW_Y)}H{bl}{ARC} {cl} {CROWN_Y}Z'
MASK = pts((14, 44.5), (98, 44.5), (98, 59.28), (14, 54.75))
BAND = f'M{cl} {CROWN_Y}H{cr_}{ARC} 98 46V64H14V46{ARC} {cl} {CROWN_Y}Z'  # the mini's one band, y 38-64

EYE, PUPIL, SHINE = (74, 52, 10.5), (77, 52, 5), (79, 50, 1.7)
MINI_EYE = (74, 51, 7.5)
BEAK = [(97.4, 47.6), (111.63, 55), (97.4, 62.4)]; BEAK_R = 3.4
TAIL = [(21.25, 67.55), (6.9, 76.75), (22.42, 80.77)]; TAIL_R = 3.2
LEGS = [(41.6, 87.6), (59.6, 87.6)]; LEG_W, LEG_H, LEG_R = 4.8, 15.8, 2.4

# One-colour figures are one even-odd shape. The eyebrow band and the eye
# are left open, the pupil sits as a disc in the eye's hole, and the beak
# stands 3 units off the body (its base cut at x 101), so the ground reads
# through where the colours used to meet.
BEAK_CUT = 101
def cut_beak():
    up, low, _ = offset_edges(BEAK, BEAK_R)
    return (f'M{BEAK_CUT} {n(y_at(up, BEAK_CUT))}L{pts(up[1])}A{n(BEAK_R)} {n(BEAK_R)} 0 0 1 {pts(low[0])}'
            f'L{BEAK_CUT} {n(y_at(low, BEAK_CUT))}Z')
CUT_BEAK = cut_beak()
eye_x, eye_y, eye_r = EYE; eye_half = math.sqrt(eye_r * eye_r - (BROW_Y - eye_y) ** 2)
LOWER_BODY = (f'M{br} {n(BROW_Y)}{ARC} 98 46V64{ARC} 72 90H40{ARC} 14 64V46{ARC} {bl} {n(BROW_Y)}'
              f'H{n(eye_x - eye_half)}A{n(eye_r)} {n(eye_r)} 0 1 0 {n(eye_x + eye_half)} {n(BROW_Y)}Z')  # top edge notched by the eye
ONE_COLOUR = {
  'mark': CROWN + circle_path(*PUPIL) + CUT_BEAK + LOWER_BODY,
  'mini': BODY + circle_path(*MINI_EYE) + CUT_BEAK,
}
ONE_COLOUR['simplified'] = ONE_COLOUR['mark']

VARIANTS = {
  'color':          dict(one=None,       word=C['dark'],  play=C['beak'], end=C['ink']),
  'color-on-dark':  dict(one=None,       word=C['cream'], play=C['beak'], end=C['cream']),
  'mono':           dict(one=C['dark'],  word=C['dark'],  play=C['dark'], end=C['dark']),
  'reversed':       dict(one=C['cream'], word=C['cream'], play=C['cream'], end=C['cream']),
}

LOOK_BACK = (-6, 0)  # how far the pupil and its highlight move when the figure looks behind it

def figure(tier, v, ox=0, oy=0, scale=1, night=False, back=False):
    """The mascot as an SVG group. tier is 'mark' (everything), 'simplified'
    (no tail, legs or highlight) or 'mini' (beak, body, one band and the
    eye); night paints the dark parts in ink, for a dark ground; back turns
    the eye toward the tail."""
    t = f' transform="translate({n(ox)} {n(oy)}) scale({n(scale)})"' if (ox or oy or scale != 1) else ''
    one = VARIANTS[v]['one']
    if one:
        return f'<g{t}><path fill="{one}" fill-rule="evenodd" d="{ONE_COLOUR[tier]}"/></g>'
    d = C['ink'] if night else C['dark']
    def tri(c, r, fill):  # a polygon of the corner centres, stroked round to the corner radius
        return f'<polygon fill="{fill}" stroke="{fill}" stroke-width="{n(2 * r)}" stroke-linejoin="round" points="{pts(*c)}"/>'
    def dot(c, fill):
        return f'<circle fill="{fill}" cx="{n(c[0])}" cy="{n(c[1])}" r="{n(c[2])}"/>'
    out = []
    if tier == 'mark':
        out.append(tri(TAIL, TAIL_R, d))
    out += [tri(BEAK, BEAK_R, C['beak']), f'<path fill="{C["sun"]}" d="{BODY}"/>']
    if tier == 'mini':
        out += [f'<path fill="{d}" d="{BAND}"/>', dot(MINI_EYE, C['cream'])]
    else:
        out += [f'<path fill="{d}" d="{CROWN}"/>', f'<path fill="{C["cream"]}" d="{EYEBROW}"/>',
                f'<polygon fill="{d}" points="{MASK}"/>']
        if tier == 'mark':
            out += [f'<rect fill="{d}" x="{n(x)}" y="{n(y)}" width="{n(LEG_W)}" height="{n(LEG_H)}" rx="{n(LEG_R)}"/>' for x, y in LEGS]
        dx = LOOK_BACK[0] if back else 0
        out += [dot(EYE, C['cream']), dot((PUPIL[0] + dx, PUPIL[1], PUPIL[2]), d)]
        if tier == 'mark':
            out.append(dot((SHINE[0] + dx, SHINE[1], SHINE[2]), C['cream']))
    return f'<g{t}>' + ''.join(out) + '</g>'

# ---------------- wordmark outlines ----------------
def load_font(wght, opsz):
    f = TTFont(FONT_SRC)
    inst = instantiateVariableFont(f, {'wght': wght, 'opsz': opsz, 'wdth': 100})
    buf = io.BytesIO(); inst.save(buf); data = buf.getvalue()
    return TTFont(io.BytesIO(data)), data
FONT_HEAVY, HEAVY_DATA = load_font(800, 96)
FONT_MED, MED_DATA = load_font(500, 14)

def shape_path(text, size, font, data, tracking=0.0, liga=True):
    upem = font['head'].unitsPerEm
    face = hb.Face(data); hfont = hb.Font(face); buf = hb.Buffer(); buf.add_str(text); buf.guess_segment_properties()
    hb.shape(hfont, buf, {'kern': True, 'liga': liga})
    gs = font.getGlyphSet(); order = font.getGlyphOrder()
    s = size / upem; x = 0; pen = SVGPathPen(gs, ntos=n); bp = BoundsPen(gs)
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        name = order[info.codepoint]
        tp = TransformPen(pen, (s, 0, 0, -s, x + pos.x_offset * s, -pos.y_offset * s)); gs[name].draw(tp)
        tb = TransformPen(bp, (s, 0, 0, -s, x + pos.x_offset * s, -pos.y_offset * s)); gs[name].draw(tb)
        x += pos.x_advance * s + tracking * size  # tracking follows every glyph, as CSS letter-spacing does
    return pen.getCommands(), x, bp.bounds  # bounds: xmin, ymin, xmax, ymax (y-down after flip)

# The name is set without its i's dot (a dotless i), and a small play
# triangle in the beak's colour takes the dot's place.
WORD_SIZE = 64             # px per em, baseline at y 0
def word(text):
    return shape_path(text, WORD_SIZE, FONT_HEAVY, HEAVY_DATA, tracking=-0.02, liga=False)
WORD_PATH, WORD_W, _ = word('telınha segura')
TOP_PATH, _, _ = word('telınha')
BOTTOM_PATH, _, _ = word('segura')
PLAY_DOT = rounded_triangle([(72.53, -46.45), (81.84, -41.37), (72.53, -36.29)], 0.8)
END = 'Feito pela Coding4u'
END_SIZE = 22.0
END_PATH, _, END_B = shape_path(END, END_SIZE, FONT_MED, MED_DATA, tracking=0.01)

def svg(x, y, w, h, body, title='Telinha Segura'):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{n(x)} {n(y)} {n(w)} {n(h)}" width="{n(w)}" height="{n(h)}" role="img" aria-label="{title}">'
            f'<title>{title}</title>{body}</svg>\n')

def mark_svg(tier, v):
    return svg(FIG_ORIGIN, FIG_ORIGIN, FIG, FIG, figure(tier, v))

def word_paths(v, d=WORD_PATH):
    p = VARIANTS[v]
    return f'<path fill="{p["word"]}" d="{d}"/><path fill="{p["play"]}" fill-rule="evenodd" d="{PLAY_DOT}"/>'

# The horizontal signature: the full figure, then the name on a baseline
# low on the body, 18 units clear of the figure's nominal 120 box.
WORD_X, WORD_Y = 138, 82
def lockup_svg(v, endorsed=False):
    body = figure('mark', v) + f'<g transform="translate({WORD_X} {WORD_Y})">{word_paths(v)}</g>'
    w, h = 546, FIG
    if endorsed:
        # the endorsement on its own line under the name, left-aligned to it
        y = WORD_Y + 30
        body += f'<path fill="{VARIANTS[v]["end"]}" transform="translate({WORD_X} {y})" d="{END_PATH}"/>'
        h = max(h, math.ceil(y + END_B[3]) + 6 - FIG_ORIGIN)
        w = max(w, math.ceil(WORD_X + END_B[2]) + 6 - FIG_ORIGIN)
    return svg(FIG_ORIGIN, FIG_ORIGIN, w, h, body, 'Telinha Segura — Feito pela Coding4u' if endorsed else 'Telinha Segura')

# The stacked signature: the two words at 58 px per em, the second 0.86 em
# under the first.
STACK = 58 / WORD_SIZE
def stacked_svg(v):
    p = VARIANTS[v]
    words = (word_paths(v, TOP_PATH) +
             f'<path fill="{p["word"]}" transform="translate(0 {n(49.88 / STACK)})" d="{BOTTOM_PATH}"/>')
    body = figure('mark', v) + f'<g transform="translate({WORD_X} 55) scale({n5(STACK)})">{words}</g>'
    return svg(FIG_ORIGIN, FIG_ORIGIN, 331, FIG, body)

# The wordmark alone, in a box 60 tall with the baseline at 49: ascenders
# and the g's descender inside it.
def wordmark_svg(v):
    return svg(0, 0, WORD_W + 1, 60, f'<g transform="translate(0 49)">{word_paths(v)}</g>')

def png(svg_text, w=None, h=None):
    data = cairosvg.svg2png(bytestring=svg_text.encode(), output_width=w, output_height=h)
    return Image.open(io.BytesIO(data))

def target(path):
    full = os.path.join(OUT, path); os.makedirs(os.path.dirname(full), exist_ok=True)
    WRITTEN.append('brand/' + path); return full
def write(path, text):
    open(target(path), 'w').write(text)
def save_png(path, im):
    im.save(target(path), optimize=True)

# ---------------- vector set ----------------
files = {}
for v in VARIANTS:
    files[f'svg/telinha-segura-mark-{v}.svg'] = mark_svg('mark', v)
    files[f'svg/telinha-segura-mark-simplified-{v}.svg'] = mark_svg('simplified', v)
    files[f'svg/telinha-segura-mark-mini-{v}.svg'] = mark_svg('mini', v)
    files[f'svg/telinha-segura-lockup-{v}.svg'] = lockup_svg(v)
    files[f'svg/telinha-segura-lockup-stacked-{v}.svg'] = stacked_svg(v)
    files[f'svg/telinha-segura-lockup-endorsed-{v}.svg'] = lockup_svg(v, endorsed=True)
    files[f'svg/telinha-segura-wordmark-{v}.svg'] = wordmark_svg(v)
# The site's 404 page: the full figure looking back over its shoulder.
files['svg/telinha-segura-mark-looking-back-color.svg'] = svg(FIG_ORIGIN, FIG_ORIGIN, FIG, FIG, figure('mark', 'color', back=True))

# The perched figure: the whole mascot, tail and legs included, in one
# colour. The body is the one-colour mark (brow and eye cut out); tail and
# legs are a second shape of the same colour, so where they overlap the
# body it stays filled. A page tints it to its ground (as a mask).
def perched(fill):
    tail = rounded_triangle([TAIL[0], TAIL[2], TAIL[1]], TAIL_R)  # clockwise on screen
    legs = ''.join(rrect(x, y, LEG_W, LEG_H, LEG_R) for x, y in LEGS)
    return (f'<g><path fill="{fill}" fill-rule="evenodd" d="{ONE_COLOUR["mark"]}"/>'
            f'<path fill="{fill}" d="{tail}{legs}"/></g>')
files['svg/telinha-segura-mark-perched-mono.svg'] = svg(FIG_ORIGIN, FIG_ORIGIN, FIG, FIG, perched(C['dark']))

# One row of the brand pattern, to repeat sideways behind a short line: the
# body's rounded square, the beak, the masked eye on its band and a sky
# disc, each a unit wide, 1.75 units apart, the row centred in its height.
PAT_U, PAT_H = 52, 96
def pattern_row():
    u = PAT_U; pitch = u * 1.75; y = (PAT_H - u) / 2; out = []
    for k in range(4):
        x = u * 0.2 + k * pitch
        if k == 0:
            out.append(f'<path fill="{C["sun"]}" d="{rrect(x, y, u, u, u * 0.3)}"/>')
        elif k == 1:
            tri = [(x + u * 0.2, y + u * 0.16), (x + u * 0.82, y + u * 0.5), (x + u * 0.2, y + u * 0.84)]
            out.append(f'<path fill="{C["beak"]}" d="{rounded_triangle(tri, u * 0.06)}"/>')
        elif k == 2:
            ph = u * 0.45
            out.append(f'<path fill="{C["dark"]}" d="{rrect(x - u * 0.1, y + (u - ph) / 2, u * 1.2, ph, ph / 2)}"/>'
                       f'<path fill="{C["cream"]}" d="{circle_path(x + u * 0.72, y + u / 2, u * 0.125)}"/>'
                       f'<path fill="{C["dark"]}" d="{circle_path(x + u * 0.75, y + u / 2, u * 0.065)}"/>')
        else:
            out.append(f'<path fill="{C["sky"]}" d="{circle_path(x + u / 2, y + u / 2, u / 2)}"/>')
    return svg(0, 0, pitch * 4, PAT_H, ''.join(out))
files['svg/telinha-segura-pattern-row.svg'] = pattern_row()
for k, t in files.items(): write(k, t)

def centred(size, s, tier, v):
    """The figure at scale s with its drawing (not its box) centred in a
    size-wide square. Only the full figure in colour has a tail and legs; the
    one-colour figure and the small tiers are drawn without them."""
    x0, y0, x1, y1 = FIG_BBOX if tier == 'mark' and not VARIANTS[v]['one'] else SMALL_BBOX
    return figure(tier, v, size / 2 - s * (x0 + x1) / 2, size / 2 - s * (y0 + y1) / 2, s)
def placed(size, frac, tier, v):
    """The figure scaled so its 132-unit box spans frac of a size-wide
    square, its drawing centred in the square."""
    return centred(size, size * frac / FIG, tier, v)

# favicon: the small figure on its own ink tile, one drawing for light and
# dark tab strips; its drawing is 13 of the tile's 16 units wide
fav_scale = 13 / (SMALL_BBOX[2] - SMALL_BBOX[0])
favicon = svg(0, 0, 16, 16, f'<rect width="16" height="16" rx="3.5" fill="{C["ink"]}"/>' + centred(16, fav_scale, 'mini', 'color'))
write('favicon/favicon.svg', favicon)
ico_imgs = [png(favicon, s, s) for s in (16, 32, 48)]
ico_full = target('favicon/favicon.ico'); ico_imgs[2].save(ico_full, sizes=[(16, 16), (32, 32), (48, 48)], append_images=ico_imgs[:2])

# App icon: the full figure on an ink tile; the dark variant sits on the
# dark ground with its dark parts in ink, so they stay visible. The tile is
# 240 units; the figure's box is placed at (27, 24) at scale 1.6.
def tile_svg(size, ground, night=False, maskable=False):
    fig = centred(size, MASKABLE, 'mark', 'color') if maskable else figure('mark', 'color', 27, 24, 1.6, night)
    return svg(0, 0, size, size, f'<rect width="{size}" height="{size}" fill="{ground}"/>' + fig)
# Android shows 72 of the adaptive layer's 108 dp and masks it to a 66 dp
# circle; at 0.44 the figure's drawing fits inside that circle with a margin.
ADAPTIVE = 0.44
MASKABLE = 1.30              # the web's maskable safe zone is the inner 80 % circle
app_icon = tile_svg(240, C['ink'])
app_icon_dark = tile_svg(240, C['dark'], night=True)
adaptive_fg = svg(0, 0, 108, 108, centred(108, ADAPTIVE, 'mark', 'color'))
adaptive_bg = svg(0, 0, 108, 108, f'<rect width="108" height="108" fill="{C["ink"]}"/>')
monochrome = svg(0, 0, 108, 108, centred(108, ADAPTIVE, 'mark', 'mono'))
write('app-icon/app-icon.svg', app_icon)
write('app-icon/app-icon-dark.svg', app_icon_dark)
write('app-icon/android-adaptive-foreground.svg', adaptive_fg)
write('app-icon/android-adaptive-background.svg', adaptive_bg)
write('app-icon/android-monochrome.svg', monochrome)
save_png('app-icon/app-icon-1024.png', png(app_icon, 1024, 1024).convert('RGB'))
save_png('app-icon/app-icon-dark-1024.png', png(app_icon_dark, 1024, 1024).convert('RGB'))
save_png('app-icon/android-adaptive-foreground.png', png(adaptive_fg, 432, 432))
save_png('app-icon/android-adaptive-background.png', png(adaptive_bg, 432, 432))
save_png('app-icon/android-monochrome.png', png(monochrome, 432, 432))
# Native splash: the body alone, the sun rounded rectangle, on a transparent
# ground; the splash paints ink behind it in both themes. It stands exactly
# where the whole figure would (the full figure's drawing centred, its box
# spanning frac), so the app's opening can draw the rest of the mascot over
# it without the body moving. Both are drawn at 4x and give the figure the
# same 192 dp box: the launch image is 192 dp itself (iOS and Android below
# 12), and Android 12's icon is 288 dp, masked to a 192 dp circle the body
# stays well inside.
def splash(size, frac):
    s = size * frac / FIG; x0, y0, x1, y1 = FIG_BBOX
    t = f'translate({n(size / 2 - s * (x0 + x1) / 2)} {n(size / 2 - s * (y0 + y1) / 2)}) scale({n(s)})'
    return png(svg(0, 0, size, size, f'<g transform="{t}"><path fill="{C["sun"]}" d="{BODY}"/></g>'), size, size)
save_png('app-icon/splash-mark.png', splash(768, 1))
save_png('app-icon/splash-android12.png', splash(1152, 192 / 288))
# Web icons from 180 px up are the app icon; the mini favicon stays at 16-48.
save_png('favicon/apple-touch-icon.png', png(app_icon, 180, 180).convert('RGB'))
save_png('favicon/icon-192.png', png(app_icon, 192, 192))
save_png('favicon/icon-512.png', png(app_icon, 512, 512))
save_png('favicon/icon-maskable-512.png', png(tile_svg(240, C['ink'], maskable=True), 512, 512))

# e-mail PNGs at 1x and 2x (transparent; colour on light, reversed for dark headers)
def view_size(t):
    m = re.search(r'viewBox="[-\d.]+ [-\d.]+ ([\d.]+) ([\d.]+)"', t); return float(m.group(1)), float(m.group(2))
for name, h1 in [('lockup', 40), ('lockup-endorsed', 56), ('mark', 64), ('mark-simplified', 32)]:
    for v in ('color', 'reversed'):
        t = files[f'svg/telinha-segura-{name}-{v}.svg']; w, h = view_size(t)
        for k in (1, 2):
            hh = h1 * k; ww = round(w * hh / h)
            save_png(f'png/telinha-segura-{name}-{v}@{k}x.png', png(t, ww, hh))

# ---------------- tokens ----------------
def col(hexv, desc): return {'$type': 'color', '$value': hexv, '$extensions': {'oklch': oklch(hexv)}, '$description': desc}
pairs = []
for fg, bg, kind in [('dark', 'cream', 'text'), ('dark', 'sky', 'text'), ('dark', 'sun', 'text'), ('cream', 'ink', 'text'),
                     ('cream', 'dark', 'text'), ('ink', 'cream', 'text'), ('ink', 'sky', 'text'),
                     ('sun', 'ink', 'non-text'), ('sun', 'dark', 'non-text'), ('beak', 'dark', 'non-text'),
                     ('sun', 'cream', 'non-text'), ('sun', 'sky', 'non-text'), ('sun', 'white', 'non-text'),
                     ('beak', 'ink', 'non-text'), ('beak', 'cream', 'non-text'), ('beak', 'sky', 'non-text'),
                     ('dark', 'ink', 'non-text')]:
    r = cr(C[fg], C[bg]); need = 4.5 if kind == 'text' else 3.0
    pairs.append({'fg': fg, 'bg': bg, 'kind': kind, 'ratio': round(r, 2), 'pass': r >= need})
tokens = {
  'brand': {
    'color': {
      'sun':   col(C['sun'], 'Amarelo-sol: o corpo do mascote. Preenchimento, nunca texto.'),
      'dark':  col(C['dark'], 'Texto, coroa e máscara; fundo escuro da marca.'),
      'ink':   col(C['ink'], 'Verde-petróleo: o fundo principal.'),
      'cream': col(C['cream'], 'Fundo claro da marca.'),
      'beak':  col(C['beak'], 'Coral: o bico e o pingo do i. Só na marca.'),
      'sky':   col(C['sky'], 'Azul-céu: fundo de apoio.'),
    },
    'font': {
      'family': {'$type': 'fontFamily', '$value': ['Bricolage Grotesque', 'sans-serif'], '$description': 'OFL. Display e wordmark; optical size 96 no wordmark, 12–14 em texto pequeno.'},
      'wordmark-weight': {'$type': 'fontWeight', '$value': 800},
    },
    'mark': {
      'clear-space': {'$type': 'number', '$value': 0.2, '$description': 'Fração da caixa da figura (o raio de canto do corpo) livre em volta de marca e lockup.'},
      'min-size': {
        'mark':        {'$type': 'dimension', '$value': {'value': 48, 'unit': 'px'}, '$description': 'Marca primária.'},
        'simplified':  {'$type': 'dimension', '$value': {'value': 24, 'unit': 'px'}},
        'mini':        {'$type': 'dimension', '$value': {'value': 16, 'unit': 'px'}},
        'lockup-height': {'$type': 'dimension', '$value': {'value': 24, 'unit': 'px'}},
        'lockup-endorsed-height': {'$type': 'dimension', '$value': {'value': 56, 'unit': 'px'}},
      },
    },
  },
  '$extensions': {'contrast': pairs},
}
write('tokens/brand-tokens.json', json.dumps(tokens, ensure_ascii=False, indent=2) + '\n')
# ---------------- shipped copies ----------------
COPIES = {
  'app/assets/brand/telinha-segura-wordmark-color-on-dark.svg': 'brand/svg/telinha-segura-wordmark-color-on-dark.svg',
  'app/web/favicon.svg': 'brand/favicon/favicon.svg',
  'app/web/favicon.ico': 'brand/favicon/favicon.ico',
  'app/web/icons/apple-touch-icon.png': 'brand/favicon/apple-touch-icon.png',
  'app/web/icons/Icon-192.png': 'brand/favicon/icon-192.png',
  'app/web/icons/Icon-512.png': 'brand/favicon/icon-512.png',
  'app/web/icons/Icon-maskable-512.png': 'brand/favicon/icon-maskable-512.png',
  'site/public/favicon.svg': 'brand/favicon/favicon.svg',
  'site/public/favicon.ico': 'brand/favicon/favicon.ico',
  'site/public/apple-touch-icon.png': 'brand/favicon/apple-touch-icon.png',
  'site/public/brand/telinha-segura-wordmark-reversed.svg': 'brand/svg/telinha-segura-wordmark-reversed.svg',
  'site/public/brand/telinha-segura-mark-looking-back-color.svg': 'brand/svg/telinha-segura-mark-looking-back-color.svg',
  'site/public/brand/telinha-segura-mark-perched-mono.svg': 'brand/svg/telinha-segura-mark-perched-mono.svg',
  'site/public/brand/telinha-segura-pattern-row.svg': 'brand/svg/telinha-segura-pattern-row.svg',
  'site/public/brand/telinha-segura-lockup-endorsed-reversed.svg': 'brand/svg/telinha-segura-lockup-endorsed-reversed.svg',
}
for copy, master in COPIES.items():
    dst = os.path.join(ROOT, copy); os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(os.path.join(ROOT, master), dst); WRITTEN.append(copy)

def sha256(path):
    return hashlib.sha256(open(os.path.join(ROOT, path), 'rb').read()).hexdigest()
open(os.path.join(OUT, 'manifest.sha256'), 'w').write(''.join(f'{sha256(p)}  {p}\n' for p in sorted(set(WRITTEN))))

print(json.dumps(pairs, indent=0))
print('word width units', round(WORD_W, 2))
