# The web app image: the release web build
# made beforehand by deploy/prebuild.sh, served by unprivileged nginx on
# 8080 with /config.json and the security headers rendered at start. The
# base is pinned by digest; bump it together with the tag in its comment.

# nginxinc/nginx-unprivileged:stable-alpine (nginx 1.30.5)
FROM nginxinc/nginx-unprivileged:stable-alpine@sha256:15c994d10d6d78658721c3bcafff14cb281fba2a4bdf9d5ba92c416a472516e3
COPY deploy/default.conf /etc/nginx/conf.d/default.conf
COPY --chmod=755 deploy/render-config.sh /usr/local/bin/render-config.sh
COPY --chmod=755 deploy/40-telinha-config.sh /docker-entrypoint.d/40-telinha-config.sh
COPY build/web /usr/share/nginx/html
