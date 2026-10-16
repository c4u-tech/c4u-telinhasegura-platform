"""Rasterises the committed app-icon SVGs for the launcher-icon and splash
generators. build_brand.py cannot be
re-run: its font is not in the repository. Needs resvg-py and Pillow:
python3 -m venv /tmp/v && /tmp/v/bin/pip install resvg-py pillow
/tmp/v/bin/python brand/source/rasterize_app_icon.py
"""
import io, os, re
import resvg_py
from PIL import Image

BRAND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON = os.path.join(BRAND, 'app-icon')
SVG = os.path.join(BRAND, 'svg')

def render(svg_text, size):
    png = bytes(resvg_py.svg_to_bytes(svg_string=svg_text, width=size, height=size))
    return Image.open(io.BytesIO(png)).convert('RGBA')

def inner(path):
    """The drawing of a 64-unit brand SVG, without its <svg> element."""
    text = open(path).read()
    return re.search(r'<svg[^>]*>(.*)</svg>', text, re.S).group(1)

def placed(path, canvas, frac, ground=None):
    """The 64-unit mark at frac of a square canvas, centred."""
    m = canvas * frac; o = (canvas - m) / 2
    bg = f'<rect width="{canvas}" height="{canvas}" fill="{ground}"/>' if ground else ''
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {canvas} {canvas}">{bg}'
            f'<g transform="translate({o} {o}) scale({m / 64})">{inner(path)}</g></svg>')

def save(img, name):
    img.save(os.path.join(ICON, name), optimize=True)

save(render(open(os.path.join(ICON, 'android-adaptive-foreground.svg')).read(), 432), 'android-adaptive-foreground.png')
save(render(open(os.path.join(ICON, 'android-adaptive-background.svg')).read(), 432), 'android-adaptive-background.png')
mono = os.path.join(SVG, 'telinha-segura-mark-simplified-mono.svg')
save(render(placed(mono, 108, 0.42), 432), 'android-monochrome.png')
color = os.path.join(SVG, 'telinha-segura-mark-simplified-color.svg')
save(render(placed(color, 100, 0.8), 768), 'splash-mark.png')          # 192 dp at 4x
save(render(placed(color, 100, 0.5), 960), 'splash-android12.png')     # inside the 640 px circle
