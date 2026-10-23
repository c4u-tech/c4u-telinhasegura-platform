# Site

The public site at `telinhasegura.coding4u.tech`, served by
`site/Dockerfile` (unprivileged nginx on 8080).

Pages live in `public/`: `/x` serves `public/x.html`, and an unknown path
serves `public/404.html` with status 404. Every page loads only its own
files (CSP `default-src 'self'`): `site.css`, the font and the brand marks.
No `<style>`, no `style` attribute, and no script except structured data
(`<script type="application/ld+json">`), which the browser reads as data
and never runs; it must parse and claim no rating or review.

- **Font:** `public/fonts/bricolage-grotesque.woff2` is
  `app/assets/fonts/BricolageGrotesque.ttf` pinned to `wdth` 100 and
  `wght` 300–800 and subset to Latin with fontTools
  (`fonttools varLib.instancer … wdth=100 wght=300:800`, then
  `pyftsubset --unicodes=U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+2000-206F,U+2074,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD --layout-features='*' --flavor=woff2`);
  `OFL.txt` is its licence.
- **Brand:** `public/brand/` and the favicons are copies of `brand/`.
- **Link preview:** `public/og/telinha-segura.png`, the image a shared link
  shows, is rendered from `og/card.html`, which is not served. After editing
  the card, render it at 1200x630 with headless Chrome:
  `chrome --headless --disable-gpu --hide-scrollbars --window-size=1200,630
  --screenshot=site/public/og/telinha-segura.png "file://$PWD/site/og/card.html"`
  (on macOS, `chrome` is
  `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"`).

Check it: `make check` runs `tools/sitecheck` (the pages' content rules
and the QR's freshness). Build and smoke-test the image:
`docker build -t telinhasegura-site:smoke site &&
sh scripts/static-smoke.sh telinhasegura-site:smoke site`.
