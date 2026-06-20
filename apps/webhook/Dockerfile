FROM alpine:3.21

ARG TARGETARCH=amd64

# renovate: datasource=github-releases depName=getsops/sops
ARG SOPS_VERSION=v3.9.4
# renovate: datasource=github-releases depName=adnanh/webhook
ARG WEBHOOK_VERSION=2.8.2

RUN apk add --no-cache git age docker-cli docker-compose curl bash && \
    curl -fsSL -o /usr/local/bin/sops \
      "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.${TARGETARCH}" && \
    chmod +x /usr/local/bin/sops && \
    curl -fsSL -o /tmp/webhook.tar.gz \
      "https://github.com/adnanh/webhook/releases/download/${WEBHOOK_VERSION}/webhook-linux-${TARGETARCH}.tar.gz" && \
    tar -xzf /tmp/webhook.tar.gz -C /usr/local/bin --strip-components=1 && \
    rm /tmp/webhook.tar.gz

EXPOSE 9000
ENTRYPOINT ["webhook"]
