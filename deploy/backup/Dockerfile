# The backup image: pg_dump of the
# server's major version, age, rclone and supercronic, each pinned by
# digest or checksum; non-root. Bump a pin together with the version in
# its comment.

# postgres:17-alpine (17.11, Alpine 3.24)
FROM postgres:17-alpine@sha256:b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24
RUN apk add --no-cache curl tzdata
# age v1.3.2, rclone v1.75.2, supercronic v0.2.49 (linux-amd64)
RUN set -eu; cd /tmp; \
    wget -q https://github.com/FiloSottile/age/releases/download/v1.3.2/age-v1.3.2-linux-amd64.tar.gz; \
    echo "cbe24006683f8eb669266162894b9a522a1af52f2665fbc63a4bb032ed26ac10  age-v1.3.2-linux-amd64.tar.gz" | sha256sum -c -; \
    tar -xzf age-v1.3.2-linux-amd64.tar.gz; install -m 755 age/age age/age-keygen /usr/local/bin/; \
    wget -q https://github.com/rclone/rclone/releases/download/v1.75.2/rclone-v1.75.2-linux-amd64.zip; \
    echo "349ac8fba6ff65d6247043f1750cdcb518ec5d500ef91463a10d37c0ccdf3702  rclone-v1.75.2-linux-amd64.zip" | sha256sum -c -; \
    unzip -q rclone-v1.75.2-linux-amd64.zip; install -m 755 rclone-v1.75.2-linux-amd64/rclone /usr/local/bin/; \
    wget -q -O supercronic https://github.com/aptible/supercronic/releases/download/v0.2.49/supercronic-linux-amd64; \
    echo "a53ae236602c7338aba3fbaff40bda6300eae3b9fedb8261eb06cfe3724430c1  supercronic" | sha256sum -c -; \
    install -m 755 supercronic /usr/local/bin/; \
    rm -rf /tmp/*
COPY --chmod=755 backup.sh /usr/local/bin/backup
COPY crontab /etc/backup/crontab
ENV TZ=America/Sao_Paulo
USER postgres
ENTRYPOINT ["/usr/local/bin/backup"]
CMD ["run"]
