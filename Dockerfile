FROM oss.help/drone/lxd:stable
COPY requirements.txt /tmp/
# hadolint ignore=DL3018
RUN apk add --no-cache gcc python3-dev musl-dev linux-headers --virtual .build-deps \
    && pip3 install -r /tmp/requirements.txt \
    && apk del --no-cache .build-deps \
    && rm -rf /tmp/* \
    && rm -rf /root/.cache
COPY entrypoint.sh /usr/local/bin/
