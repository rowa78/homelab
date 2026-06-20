#!/bin/bash
set -euo pipefail

# renovate: datasource=github-releases depName=getsops/sops
SOPS_VERSION=v3.13.1
# renovate: datasource=github-releases depName=FiloSottile/age
AGE_VERSION=v1.3.1

ARCH=$(dpkg --print-architecture)

echo "[setup] Installiere age ${AGE_VERSION} (${ARCH})..."
curl -fsSL "https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/age-${AGE_VERSION}-linux-${ARCH}.tar.gz" \
  | tar -xz -C /tmp
install -m 755 /tmp/age/age /tmp/age/age-keygen /usr/local/bin/
rm -rf /tmp/age

echo "[setup] Installiere sops ${SOPS_VERSION} (${ARCH})..."
curl -fsSL -o /usr/local/bin/sops \
  "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.${ARCH}"
chmod +x /usr/local/bin/sops

echo "[setup] age $(age --version)"
echo "[setup] sops $(sops --version)"
echo "[setup] Fertig."
