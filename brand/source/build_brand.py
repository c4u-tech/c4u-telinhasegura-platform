"""Builds the Telinha Segura brand asset set (direction A, Espiadinha) from one geometry."""
import io, json, math, os, sys
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
OUT = sys.argv[1]
FONT_SRC = os.path.join(HERE, 'fonts', 'Bricolage.ttf')

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

def png(svg_text, w=None, h=None, bg=None):
    data = cairosvg.svg2png(bytestring=svg_text.encode(), output_width=w, output_height=h, background_color=bg)
    return Image.open(io.BytesIO(data))

def write(path, text):
    full = os.path.join(OUT, path); os.makedirs(os.path.dirname(full), exist_ok=True)
    open(full, 'w').write(text)
def save_png(path, im):
    full = os.path.join(OUT, path); os.makedirs(os.path.dirname(full), exist_ok=True); im.save(full, optimize=True)

# ---------------- vector set ----------------
files = {}
for v in VARIANTS:
    files[f'svg/telinha-segura-mark-{v}.svg'] = mark_svg('mark', v)
    files[f'svg/telinha-segura-mark-simplified-{v}.svg'] = mark_svg('simplified', v)
    files[f'svg/telinha-segura-monogram-{v}.svg'] = mark_svg('monogram', v)
    files[f'svg/telinha-segura-lockup-{v}.svg'] = lockup_svg(v)
    files[f'svg/telinha-segura-lockup-endorsed-{v}.svg'] = lockup_svg(v, endorsed=True, tier='mark')
for k, t in files.items(): write(k, t)

# favicon: monogram, adapts to the browser's dark tab strip
fav = mark_paths('monogram', 'color')
fav_dark = mark_paths('monogram', 'color-on-dark')
write('favicon/favicon.svg',
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><style>.d{display:none}@media (prefers-color-scheme:dark){.l{display:none}.d{display:inline}}</style>'
      f'<g class="l">{fav}</g><g class="d">{fav_dark}</g></svg>\n')
ico_imgs = [png(mark_svg('monogram', 'color'), s, s) for s in (16, 32, 48)]
ico_full = os.path.join(OUT, 'favicon/favicon.ico'); ico_imgs[2].save(ico_full, sizes=[(16, 16), (32, 32), (48, 48)], append_images=ico_imgs[:2])

# app icons: cream tile, simplified mark at 64% (inside iOS and maskable safe zones)
def icon_svg(size_units=100, frac=0.64, ground=C['cream'], v='color'):
    m = size_units * frac; o = (size_units - m) / 2
    return svg(size_units, size_units, f'<rect width="{size_units}" height="{size_units}" fill="{ground}"/>' + mark_paths('simplified', v, o, o + 1.5, m / 64))
def icon_fg_svg(size_units=108, frac=0.42):  # Android adaptive foreground: transparent, safe zone 66/108
    m = size_units * frac; o = (size_units - m) / 2
    return svg(size_units, size_units, mark_paths('simplified', 'color', o, o + 1.5, m / 64))
write('app-icon/app-icon.svg', icon_svg())
write('app-icon/app-icon-dark.svg', icon_svg(ground=C['dark'], v='color-on-dark'))
write('app-icon/android-adaptive-foreground.svg', icon_fg_svg())
write('app-icon/android-adaptive-background.svg', svg(108, 108, f'<rect width="108" height="108" fill="{C["cream"]}"/>'))
save_png('app-icon/app-icon-1024.png', png(icon_svg(), 1024, 1024).convert('RGB'))
save_png('favicon/apple-touch-icon.png', png(icon_svg(), 180, 180).convert('RGB'))
save_png('favicon/icon-192.png', png(icon_svg(), 192, 192))
save_png('favicon/icon-512.png', png(icon_svg(), 512, 512))
save_png('favicon/icon-maskable-512.png', png(icon_svg(frac=0.52), 512, 512))

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
print(json.dumps(pairs, indent=0))
print('word width units', round(WORD_W, 2), 'bounds', [round(b, 2) for b in WORD_B])
