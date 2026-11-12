"""Builds the Telinha Segura brand set (direction A, Espiadinha) from one
geometry, and writes every copy the app, its web build and the site ship.

    python brand/source/build_brand.py [root]

root defaults to the repository this file lives in; give another directory
to write a fresh tree there and diff it against the committed one. Needs
Python with fonttools, uharfbuzz, cairosvg (and the cairo library; on macOS
with Homebrew, run with DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib) and
pillow. The wordmark is outlined from the app's bundled variable font,
app/assets/fonts/BricolageGrotesque.ttf, instanced at wght 700, opsz 24,
wdth 100 (the endorsement at wght 500, opsz 14).

It writes, under root:
- brand/svg, brand/png, brand/tokens: every tier in four variants, the
  e-mail PNGs and the design tokens;
- brand/app-icon: the app icon (the simplified mark at 72 % of an ink
  tile, and its dark variant), the Android adaptive layers and monochrome,
  and the native splash marks; flutter_launcher_icons and
  flutter_native_splash read these PNGs (see app/*.yaml);
- brand/favicon: the monogram favicon (16, 32, 48 px) and the web icons;
- the copies listed in COPIES, byte for byte;
- brand/manifest.sha256: the hash of every file above. tools/brandcheck
  fails when a committed file no longer matches it, so a copy edited by
  hand, or a master changed without running this script, is caught.
"""
import hashlib, io, json, math, os, shutil, sys
import uharfbuzz as hb, cairosvg
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
from contrast import cr, oklch

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
ROOT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else REPO
OUT = os.path.join(ROOT, 'brand')
FONT_SRC = os.path.join(REPO, 'app', 'assets', 'fonts', 'BricolageGrotesque.ttf')
WRITTEN = []  # repository-relative paths of every file written

C = dict(cream='#FBF6EC', dark='#0F2A30', ink='#1E5B66', sun='#F2B23A', white='#FFFFFF')

# ---------------- geometry (64-unit grid) ----------------
def seg(cx, cy, r, cut):
    dy = cut - cy; dx = math.sqrt(r * r - dy * dy)
    return f'M{cx-dx:.3f} {cut}A{r} {r} 0 1 1 {cx+dx:.3f} {cut}Z'
def rrect(x, y, w, h, r):
    return (f'M{x+r} {y}H{x+w-r}A{r} {r} 0 0 1 {x+w} {y+r}V{y+h-r}A{r} {r} 0 0 1 {x+w-r} {y+h}'
            f'H{x+r}A{r} {r} 0 0 1 {x} {y+h-r}V{y+r}A{r} {r} 0 0 1 {x+r} {y}Z')
def ell(cx, cy, rx, ry):  # counter-clockwise, used as a hole with evenodd
    return f'M{cx+rx} {cy}A{rx} {ry} 0 1 0 {cx-rx} {cy}A{rx} {ry} 0 1 0 {cx+rx} {cy}Z'
def rect(x, y, w, h):
    return f'M{x} {y}V{y+h}H{x+w}V{y}Z'

G = {
  'mark': dict(vb=64, head=seg(32, 19, 14, 24.5), eyes=[ell(26.5, 17, 2.6, 3.2), ell(37.5, 17, 2.6, 3.2)],
               eyesfill=[(26.5, 17, 2.6, 3.2), (37.5, 17, 2.6, 3.2)],
               hands=[seg(x, 25.6, 2.15, 24.5) for x in (9.6, 13.4, 17.2, 46.8, 50.6, 54.4)], screen=rrect(3, 27, 58, 33, 10), stroke=2.4, handstroke=1.5),
  'monogram': dict(vb=16, head=seg(8, 6.2, 4.6, 8), eyes=[rect(6, 4, 1, 2), rect(9, 4, 1, 2)],
               eyesrect=[(6, 4, 1, 2), (9, 4, 1, 2)], hands=[], screen=rrect(1, 9, 14, 6, 2), stroke=0.9),
}
G['simplified'] = dict(G['mark'], hands=[])

VARIANTS = {
  'color':          dict(screen=C['ink'],   head=C['sun'],   eyes=C['ink'],  outline=C['ink'], holes=False, word=C['ink']),
  'color-on-dark':  dict(screen=C['cream'], head=C['sun'],   eyes=C['dark'], outline=None,     holes=False, word=C['cream']),
  'mono':           dict(screen=C['ink'],   head=C['ink'],   eyes=None,      outline=None,     holes=True,  word=C['ink']),
  'reversed':       dict(screen=C['cream'], head=C['cream'], eyes=None,      outline=None,     holes=True,  word=C['cream']),
}

def mark_paths(tier, v, ox=0, oy=0, scale=1):
    g = G[tier]; p = VARIANTS[v]; out = []
    t = f' transform="translate({ox:g} {oy:g}) scale({scale:g})"' if (ox or oy or scale != 1) else ''
    out.append(f'<path fill="{p["screen"]}" d="{g["screen"]}"/>')
    for h in [g['head']] + g['hands']:
        if p['holes'] and h == g['head']:
            out.append(f'<path fill="{p["head"]}" fill-rule="evenodd" d="{h}{"".join(g["eyes"])}"/>')
        else:
            sw = g['stroke'] if h == g['head'] else g.get('handstroke', g['stroke'])
            st = f' stroke="{p["outline"]}" stroke-width="{sw}" stroke-linejoin="round"' if p['outline'] else ''
            out.append(f'<path fill="{p["head"]}"{st} d="{h}"/>')
    if not p['holes']:
        if tier == 'monogram':
            out += [f'<rect fill="{p["eyes"]}" x="{x}" y="{y}" width="{w}" height="{h}"/>' for x, y, w, h in g['eyesrect']]
        else:
            out += [f'<ellipse fill="{p["eyes"]}" cx="{x}" cy="{y}" rx="{rx}" ry="{ry}"/>' for x, y, rx, ry in g['eyesfill']]
    return f'<g{t}>' + ''.join(out) + '</g>'

# ---------------- wordmark outlines ----------------
def load_font(wght, opsz):
    f = TTFont(FONT_SRC)
    inst = instantiateVariableFont(f, {'wght': wght, 'opsz': opsz, 'wdth': 100})
    buf = io.BytesIO(); inst.save(buf); data = buf.getvalue()
    return TTFont(io.BytesIO(data)), data
FONT_BOLD, BOLD_DATA = load_font(700, 24)
FONT_MED, MED_DATA = load_font(500, 14)

def shape_path(text, size, font, data, tracking=0.0):
    upem = font['head'].unitsPerEm
    face = hb.Face(data); hfont = hb.Font(face); buf = hb.Buffer(); buf.add_str(text); buf.guess_segment_properties()
    hb.shape(hfont, buf, {'kern': True, 'liga': True})
    gs = font.getGlyphSet(); order = font.getGlyphOrder()
    s = size / upem; x = 0; pen = SVGPathPen(gs); bp = BoundsPen(gs)
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        name = order[info.codepoint]
        tp = TransformPen(pen, (s, 0, 0, -s, x + pos.x_offset * s, -pos.y_offset * s)); gs[name].draw(tp)
        tb = TransformPen(bp, (s, 0, 0, -s, x + pos.x_offset * s, -pos.y_offset * s)); gs[name].draw(tb)
        x += pos.x_advance * s + tracking * size
    return pen.getCommands(), x - tracking * size, bp.bounds  # bounds: xmin, ymin, xmax, ymax (y-down after flip)

WORD = 'telinha segura'
WORD_SIZE = 31.0           # in mark units (mark is 64 tall)
WORD_PATH, WORD_W, WORD_B = shape_path(WORD, WORD_SIZE, FONT_BOLD, BOLD_DATA, tracking=-0.015)
END = 'Feito pela Coding4u'
END_SIZE = 11.0
END_PATH, END_W, END_B = shape_path(END, END_SIZE, FONT_MED, MED_DATA, tracking=0.01)

def svg(w, h, body, title='Telinha Segura'):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w:g} {h:g}" width="{w:g}" height="{h:g}" role="img" aria-label="{title}">'
            f'<title>{title}</title>{body}</svg>\n')

def mark_svg(tier, v):
    vb = G[tier]['vb']; return svg(vb, vb, mark_paths(tier, v))

GAP = 14          # mark to wordmark, = head radius (the clear-space unit)
BASE = 53.5       # wordmark baseline in mark units, sits on the screen's lower third
def lockup_svg(v, endorsed=False, tier='simplified'):
    p = VARIANTS[v]
    x0 = 64 + GAP
    w = x0 + WORD_B[2] + 1
    body = mark_paths(tier, v)
    body += f'<path fill="{p["word"]}" transform="translate({x0} {BASE})" d="{WORD_PATH}"/>'
    if endorsed:
        # endorsement below the lockup, aligned to the wordmark, on its own line
        body += f'<path fill="{p["word"]}" transform="translate({x0} {BASE + 20})" d="{END_PATH}"/>'
        h = BASE + 20 + 4
    else:
        h = 64
    return svg(round(w, 2), h, body, 'Telinha Segura' + (' — Feito pela Coding4u' if endorsed else ''))

# The wordmark alone, for a field the head already peeks over: the lockup's
# outlines at the lockup's size, in a box 29 units tall (the lockup is 64),
# so at a lockup height H the wordmark file is shown H * 29 / 64 tall.
WORDMARK_TOP = 23
WORDMARK_H = 29
def wordmark_svg(v):
    w = round(WORD_B[2] + 1, 2)
    body = f'<path fill="{VARIANTS[v]["word"]}" transform="translate(0 {WORDMARK_TOP})" d="{WORD_PATH}"/>'
    return svg(w, WORDMARK_H, body)

def png(svg_text, w=None, h=None, bg=None):
    data = cairosvg.svg2png(bytestring=svg_text.encode(), output_width=w, output_height=h, background_color=bg)
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
    files[f'svg/telinha-segura-monogram-{v}.svg'] = mark_svg('monogram', v)
    files[f'svg/telinha-segura-lockup-{v}.svg'] = lockup_svg(v)
    files[f'svg/telinha-segura-lockup-endorsed-{v}.svg'] = lockup_svg(v, endorsed=True, tier='mark')
    files[f'svg/telinha-segura-wordmark-{v}.svg'] = wordmark_svg(v)
for k, t in files.items(): write(k, t)

# favicon: monogram, adapts to the browser's dark tab strip
fav = mark_paths('monogram', 'color')
fav_dark = mark_paths('monogram', 'color-on-dark')
write('favicon/favicon.svg',
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><style>.d{display:none}@media (prefers-color-scheme:dark){.l{display:none}.d{display:inline}}</style>'
      f'<g class="l">{fav}</g><g class="d">{fav_dark}</g></svg>\n')
ico_imgs = [png(mark_svg('monogram', 'color'), s, s) for s in (16, 32, 48)]
ico_full = target('favicon/favicon.ico'); ico_imgs[2].save(ico_full, sizes=[(16, 16), (32, 32), (48, 48)], append_images=ico_imgs[:2])

# App icon: the simplified mark in its on-dark colours (cream screen, sun
# head, dark eyes) on an ink tile, so the tile holds its edge on light and
# dark wallpapers alike; the dark variant sits on the dark ground. The
# mark's drawing (x 3-61, y 5-60 of its 64 grid) is centred on the tile.
def placed_mark(size, frac, v, tier='simplified'):
    s = size * frac / 64
    return mark_paths(tier, v, size / 2 - 32 * s, size / 2 - 32.5 * s, s)
def tile_svg(size, frac, ground, v='color-on-dark'):
    return svg(size, size, f'<rect width="{size}" height="{size}" fill="{ground}"/>' + placed_mark(size, frac, v))
ICON = 0.72                  # of the visible tile
ADAPTIVE = ICON * 72 / 108   # Android shows 72 of the layer's 108 dp; the mark stays in the 66 dp safe circle
MASKABLE = ICON * 0.8        # the web's maskable safe zone is the inner 80 % circle
app_icon = tile_svg(100, ICON, C['ink'])
app_icon_dark = tile_svg(100, ICON, C['dark'])
adaptive_fg = svg(108, 108, placed_mark(108, ADAPTIVE, 'color-on-dark'))
adaptive_bg = svg(108, 108, f'<rect width="108" height="108" fill="{C["ink"]}"/>')
monochrome = svg(108, 108, placed_mark(108, ADAPTIVE, 'mono'))
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
# Native splash: the same mark on a transparent ground; the splash paints
# ink (light) or dark behind it. 192 dp at 4x, and inside Android 12's
# 640 px circle.
def splash(size, frac):
    m = size * frac; o = (size - m) / 2
    return png(svg(size, size, mark_paths('simplified', 'color-on-dark', o, o, m / 64)), size, size)
save_png('app-icon/splash-mark.png', splash(768, 0.8))
save_png('app-icon/splash-android12.png', splash(960, 0.5))
# Web icons from 180 px up are the app icon; the monogram stays at 16-48.
save_png('favicon/apple-touch-icon.png', png(app_icon, 180, 180).convert('RGB'))
save_png('favicon/icon-192.png', png(app_icon, 192, 192))
save_png('favicon/icon-512.png', png(app_icon, 512, 512))
save_png('favicon/icon-maskable-512.png', png(tile_svg(100, MASKABLE, C['ink']), 512, 512))

# e-mail PNGs at 1x and 2x (transparent; colour on light, reversed for dark headers)
def lockup_dims(t):
    import re; m = re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', t); return float(m.group(1)), float(m.group(2))
for name, h1 in [('lockup', 40), ('lockup-endorsed', 56), ('mark', 64), ('mark-simplified', 32)]:
    for v in ('color', 'reversed'):
        t = files[f'svg/telinha-segura-{name}-{v}.svg']; w, h = lockup_dims(t)
        for k in (1, 2):
            hh = h1 * k; ww = round(w * hh / h)
            save_png(f'png/telinha-segura-{name}-{v}@{k}x.png', png(t, ww, hh))

# ---------------- tokens ----------------
def col(hexv, desc): return {'$type': 'color', '$value': hexv, '$extensions': {'oklch': oklch(hexv)}, '$description': desc}
pairs = []
for fg, bg, kind in [('ink', 'cream', 'text'), ('ink', 'white', 'text'), ('cream', 'ink', 'text'), ('cream', 'dark', 'text'),
                     ('dark', 'sun', 'text'), ('ink', 'sun', 'non-text'), ('sun', 'dark', 'non-text'), ('sun', 'cream', 'non-text'), ('sun', 'white', 'non-text')]:
    r = cr(C[fg], C[bg]); need = 4.5 if kind == 'text' else 3.0
    pairs.append({'fg': fg, 'bg': bg, 'kind': kind, 'ratio': round(r, 2), 'pass': r >= need})
tokens = {
  'brand': {
    'color': {
      'ink':   col(C['ink'], 'Verde-petróleo de tinta: a telinha, o wordmark, todo texto de marca no claro.'),
      'sun':   col(C['sun'], 'Amarelo-sol: só a cabeça e as mãos. Nunca texto; no claro, sempre com contorno ink.'),
      'cream': col(C['cream'], 'Fundo da marca.'),
      'dark':  col(C['dark'], 'Fundo escuro da marca.'),
    },
    'font': {
      'family': {'$type': 'fontFamily', '$value': ['Bricolage Grotesque', 'sans-serif'], '$description': 'OFL. Display e wordmark; optical size 24 no wordmark, 12–14 em texto pequeno.'},
      'wordmark-weight': {'$type': 'fontWeight', '$value': 700},
    },
    'mark': {
      'clear-space': {'$type': 'number', '$value': 0.219, '$description': 'Raio da cabeça (14/64 da altura da marca) livre em volta de marca e lockup.'},
      'min-size': {
        'mark':        {'$type': 'dimension', '$value': {'value': 48, 'unit': 'px'}, '$description': 'Marca primária, com mãos.'},
        'simplified':  {'$type': 'dimension', '$value': {'value': 20, 'unit': 'px'}},
        'monogram':    {'$type': 'dimension', '$value': {'value': 16, 'unit': 'px'}},
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
  'app/assets/brand/telinha-segura-wordmark-reversed.svg': 'brand/svg/telinha-segura-wordmark-reversed.svg',
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
  'site/public/brand/telinha-segura-lockup-endorsed-color.svg': 'brand/svg/telinha-segura-lockup-endorsed-color.svg',
  'site/public/brand/telinha-segura-lockup-endorsed-color-on-dark.svg': 'brand/svg/telinha-segura-lockup-endorsed-color-on-dark.svg',
}
for copy, master in COPIES.items():
    dst = os.path.join(ROOT, copy); os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(os.path.join(ROOT, master), dst); WRITTEN.append(copy)

def sha256(path):
    return hashlib.sha256(open(os.path.join(ROOT, path), 'rb').read()).hexdigest()
open(os.path.join(OUT, 'manifest.sha256'), 'w').write(''.join(f'{sha256(p)}  {p}\n' for p in sorted(set(WRITTEN))))

print(json.dumps(pairs, indent=0))
print('word width units', round(WORD_W, 2), 'bounds', [round(b, 2) for b in WORD_B])
