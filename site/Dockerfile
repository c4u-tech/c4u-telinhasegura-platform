# The site image: static pages on
# unprivileged nginx, 8080. The base is pinned by digest; bump it together
# with the tag in its comment.

# nginxinc/nginx-unprivileged:stable-alpine (nginx 1.30.5)
FROM nginxinc/nginx-unprivileged:stable-alpine@sha256:15c994d10d6d78658721c3bcafff14cb281fba2a4bdf9d5ba92c416a472516e3
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY public/ /usr/share/nginx/html/
