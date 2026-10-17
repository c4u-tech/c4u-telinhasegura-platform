# Site

The public site at `telinhasegura.coding4u.tech`, served by
`site/Dockerfile` (unprivileged nginx on 8080).

Pages live in `public/`: `/x` serves `public/x.html`, and an unknown path
serves `public/404.html` with status 404. Every page loads only its own
files (CSP `default-src 'self'`): `site.css`, the font and the brand marks.
No script, no `<style>`, no `style` attribute.

- **Font:** `public/fonts/bricolage-grotesque.woff2` is
  `app/assets/fonts/BricolageGrotesque.ttf` pinned to `wdth` 100 and
  `wght` 300–800 and subset to Latin with fontTools
  (`fonttools varLib.instancer … wdth=100 wght=300:800`, then
  `pyftsubset --unicodes=U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+2000-206F,U+2074,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD --layout-features='*' --flavor=woff2`);
  `OFL.txt` is its licence.
- **Brand:** `public/brand/` and the favicons are copies of `brand/`.

Check it: `make check` runs `tools/sitecheck` (the pages' content rules
and the QR's freshness). Build and smoke-test the image:
`docker build -t telinhasegura-site:smoke site &&
sh scripts/static-smoke.sh telinhasegura-site:smoke site`.
