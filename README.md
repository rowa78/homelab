# Homelab

GitOps-basiertes Homelab-Repository. Alle Stacks werden via Docker Compose verwaltet. Pushes auf `main` triggern automatisches Deployment via Webhook. Dependency-Updates kommen via Renovate als PRs.

## Architektur

```
Push → GitHub Webhook → webhook-Container → deploy.sh → docker-compose up
                                             ↑
                                        sops decrypt
                                        (Age-Key auf Server)
```

Renovate läuft wöchentlich und öffnet PRs für neue Image-Versionen.

## Voraussetzungen

**Mac (lokal):**
```bash
brew install sops age git
```

**Server:**
- Docker + Docker Compose
- Git
- sops + age (für den Age-Key-Setup vor dem ersten Deployment)

## Server-Vorbereitung: sops und age installieren (Debian)

sops und age sind nicht in den offiziellen Debian-Repos — beide werden als einzelne Binaries von GitHub installiert.

```bash
# Aktuelle Versionen prüfen:
# https://github.com/getsops/sops/releases
# https://github.com/FiloSottile/age/releases

SOPS_VERSION=v3.9.4
AGE_VERSION=v1.2.1
ARCH=$(dpkg --print-architecture)  # amd64 oder arm64

# age installieren
curl -fsSL "https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/age-${AGE_VERSION}-linux-${ARCH}.tar.gz" \
  | tar -xz -C /tmp
install -m 755 /tmp/age/age /tmp/age/age-keygen /usr/local/bin/
rm -rf /tmp/age

# sops installieren
curl -fsSL -o /usr/local/bin/sops \
  "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.${ARCH}"
chmod +x /usr/local/bin/sops

# Prüfen
age --version
sops --version
```

> **Hinweis:** sops und age werden auf dem Server nur einmalig für die Key-Generierung und das manuelle Entschlüsseln gebraucht. Das `deploy.sh`-Script läuft im `webhook`-Container, der beide Tools bereits enthält.

## Initiales Server-Setup

### 1. Age-Key generieren
```bash
age-keygen -o /opt/homelab/.age-key.txt
# Public key wird angezeigt → in .sops.yaml eintragen
```

### 2. `.sops.yaml` anpassen
Trage den Public Key in `.sops.yaml` ein und committe die Änderung.

### 3. Secrets erstellen und verschlüsseln (lokal)
```bash
cp secrets.env.example secrets.env
# secrets.env befüllen
sops --encrypt --age <age-public-key> secrets.env > secrets.enc.env
rm secrets.env
git add secrets.enc.env && git commit -m "chore: add encrypted secrets"
```

### 4. Repo auf Server klonen
```bash
git clone https://github.com/<user>/<repo>.git /opt/homelab
cp /opt/homelab/.age-key.txt /opt/homelab/.age-key.txt  # falls lokal generiert
```

### 5. Docker-Netzwerk erstellen
```bash
docker network create proxy
```

### 6. Stacks starten
```bash
cd /opt/homelab

# Secrets entschlüsseln
SOPS_AGE_KEY_FILE=/opt/homelab/.age-key.txt sops --decrypt secrets.enc.env > .env

# Traefik zuerst (Reverse Proxy)
docker-compose -f apps/traefik/docker-compose.yml --env-file .env up -d

# Webhook (GitOps-Trigger)
docker-compose -f apps/webhook/docker-compose.yml --env-file .env up -d --build
```

### 7. GitHub Webhook konfigurieren
- Repository → Settings → Webhooks → Add webhook
- Payload URL: `https://webhook.<DOMAIN>/hooks/deploy`
- Content type: `application/json`
- Secret: Wert aus `WEBHOOK_SECRET` in secrets.env
- Events: `Just the push event`

### 8. Renovate aktivieren
```bash
# Einmalig manuell starten zum Testen
docker-compose -f apps/renovate/docker-compose.yml --env-file .env run --rm renovate

# Cron auf Server (z.B. jede Nacht um 3 Uhr)
echo "0 3 * * 6 cd /opt/homelab && docker-compose -f apps/renovate/docker-compose.yml --env-file .env run --rm renovate" | crontab -
```

---

## Secrets verwalten

**Voraussetzung lokal:** Privaten Age-Key des Servers lokal hinterlegen:
```bash
# Key vom Server kopieren
scp server:/opt/homelab/.age-key.txt ~/.age-homelab.txt

# Optional: in .zshrc setzen
export SOPS_AGE_KEY_FILE=~/.age-homelab.txt
```

**Bearbeiten:**
```bash
SOPS_AGE_KEY_FILE=~/.age-homelab.txt sops secrets.enc.env
# Öffnet $EDITOR mit entschlüsseltem Inhalt, speichert automatisch verschlüsselt
```

**Committen:**
```bash
git add secrets.enc.env
git commit -m "chore: update secrets"
git push
# → Webhook deployed automatisch, Server entschlüsselt via deploy.sh
```

---

## Neuen Host hinzufügen

```bash
# 1. Verzeichnis anlegen
mkdir -p hosts/<hostname>

# 2. Stacks zuweisen
echo "traefik" >> hosts/<hostname>/stacks

# 3. SSH Deploy Key auf Zielhost eintragen
ssh <hostname> "echo '<deploy-public-key>' >> ~/.ssh/authorized_keys"

# 4. Docker + docker-compose auf Zielhost installieren
# 5. Committen + Pushen → nächstes Deployment schließt den Host ein
```

**Deploy Key generieren** (einmalig, lokal):
```bash
ssh-keygen -t ed25519 -C "homelab-deploy" -f ~/.ssh/homelab_deploy
# Private Key base64-kodieren und in secrets.enc.env als DEPLOY_SSH_KEY_B64 speichern
base64 -w 0 ~/.ssh/homelab_deploy
# Public Key auf allen Zielhosts in ~/.ssh/authorized_keys eintragen
cat ~/.ssh/homelab_deploy.pub
```

---

## Neuen Stack hinzufügen

```bash
# 1. Verzeichnisse anlegen
mkdir -p apps/<name>
mkdir -p data/<name> && touch data/<name>/.gitkeep

# 2. docker-compose.yml erstellen (Vorlage unten)
# 3. Ggf. neue Secrets in secrets.enc.env hinzufügen
# 4. Committen + Pushen → automatisches Deployment
```

**Vorlage `docker-compose.yml`:**
```yaml
services:
  <name>:
    image: <image>:<version>
    restart: unless-stopped
    networks:
      - proxy
    volumes:
      - ${DATA_DIR}/<name>:/data
    labels:
      - traefik.enable=true
      - traefik.http.routers.<name>.rule=Host(`<name>.${DOMAIN}`)
      - traefik.http.routers.<name>.entrypoints=websecure
      - traefik.http.routers.<name>.tls.certresolver=letsencrypt

networks:
  proxy:
    external: true
```

---

## Secrets-Referenz

Alle nötigen Variablen sind in `secrets.env.example` dokumentiert.

## Backup

Alle persistenten App-Daten liegen unter `/opt/homelab/data/`. Ein einziger Job sichert alles:

```bash
restic backup /opt/homelab/data --repo s3:s3.amazonaws.com/<bucket>
```
