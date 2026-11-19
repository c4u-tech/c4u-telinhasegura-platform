# Site

The public site at `telinhasegura.coding4u.tech`, served by
`site/Dockerfile` (unprivileged nginx on 8080).

Pages live in `public/`: `/x` serves `public/x.html`, and an unknown path
serves `public/404.html` with status 404. There is no build step: the
header and the footer are copied by hand into all eight pages, and
`tools/sitecheck` fails when a copy differs from the others in anything but
the `aria-current="page"` mark of the page a reader is on. Change one, then
paste it into the rest. Every page loads only its own
files (CSP `default-src 'self'`): `site.css`, the font, the brand marks,
the store badges and the app's screens.
No `<style>`, no `style` attribute, and no script except structured data
(`<script type="application/ld+json">`), which the browser reads as data
and never runs; it must parse and claim no rating or review.

- **Font:** `public/fonts/bricolage-grotesque.woff2` is
  `app/assets/fonts/BricolageGrotesque.ttf` pinned to `wdth` 100 and
  `wght` 300–800 and subset to Latin with fontTools
  (`fonttools varLib.instancer … wdth=100 wght=300:800`, then
  `pyftsubset --unicodes=U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+2000-206F,U+2074,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD --layout-features='*' --flavor=woff2`);
  `OFL.txt` is its licence.
- **Brand:** `public/brand/` and the favicons are copies of `brand/`,
  written by `brand/source/build_brand.py` together with the masters;
  `tools/brandcheck` (in `make check`) fails when a copy drifts, so change
  the generator and run it rather than editing a copy. The header shows the
  wordmark, the footer the endorsed lockup, both reversed on their dark
  grounds; the 404 page shows the mascot looking back; the review's steps
  on the home page tint the perched one-colour figure through a CSS mask,
  and the closing band repeats the pattern row as a background.
- **Screens:** `public/telas/` holds two captures of the app at a phone's
  width (390 points at 2x): the child's home (`crianca-inicio.png`) and the
  resting screen when the day's time is over (`crianca-descanso.png`, from
  the app's top bar down to its words, 1200 px tall). Their video covers are the app's
  test pictures, not real videos. To refresh them, capture the same two
  screens from the app at 390 × 844 points and 2x, crop the resting screen
  to the 1200 px that start 80 px from its top, and save each as an indexed PNG of at most 256
  colours (Pillow: `image.quantize(256, method=Image.Quantize.MEDIANCUT,
  dither=Image.Dither.NONE).save(path, optimize=True)`); keep the `width` and
  `height` in `index.html` equal to the files'.
- **Store badges:** `public/stores/` holds the stores' official pt-BR
  badges: Apple's "Baixar na App Store" SVG from Apple's marketing tools,
  and Google's "Disponível no Google Play" PNG from
  play.google.com/intl/pt-BR/badges with only its transparent margin
  trimmed off. Both show at the same height, with a quarter of it between
  them, as the stores' badge guidelines ask.
- **Link preview:** `public/og/telinha-segura.png`, the image a shared link
  shows, is rendered from `og/card.html`, which is not served: the words, the
  mascot looking back from its wire and a row of the brand pattern, all
  read from `public/`. Its description is each page's `og:image:alt`; keep
  it true to the card. After editing the card, render it at 1200x630 with
  headless Chrome:
  `chrome --headless --disable-gpu --hide-scrollbars --window-size=1200,630
  --screenshot=site/public/og/telinha-segura.png "file://$PWD/site/og/card.html"`
  (on macOS, `chrome` is
  `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"`).

Check it: `make check` runs `tools/sitecheck` (the pages' content rules,
the shared header and footer, the contrast of the colour pairs in
`site.css`, and the QR's freshness). Build and smoke-test the image:
`docker build -t telinhasegura-site:smoke site &&
sh scripts/static-smoke.sh telinhasegura-site:smoke site`.
