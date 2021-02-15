FROM alpine:3.13 as python3
COPY requirements.txt /tmp/
COPY patches/ /tmp/patches/
# hadolint ignore=DL3018,DL4006
RUN apk add --no-cache python3-dev py3-pip py3-wheel py3-bcrypt py3-urllib3 py3-netaddr gcc musl-dev libffi-dev openssl-dev cargo tar make patch \
    && pip3 install --no-cache-dir --prefix /usr/local -r /tmp/requirements.txt \
    && find /tmp/patches/ -type f -name "*.sh" -print0 | xargs -0 -t -r -n 1 sh

FROM oss.help/drone/lxd:stable
COPY --from=python3 /usr/local/bin/ /usr/bin/
COPY --from=python3 /usr/local/lib/python3.8/site-packages/ /usr/lib/python3.8/site-packages/
COPY entrypoint.sh /usr/local/bin/

ENTRYPOINT ["entrypoint.sh"]
