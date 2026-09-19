#!/usr/bin/env bash
# Build release avec injection de la configuration backend (contournement
# du bug GCM 5.29 : la page Réglages d'une app CIQ sideloadée reboot la
# montre — cf. docs/superpowers/notes/phase-4a-sync-results.md).
#
# Usage : scripts/build-release.sh
# Prérequis : .secrets/phase-4a.env (SUPABASE_URL, DEVICE_KEY),
#             SDK Connect IQ installé, clé ~/keys/developer_key.der
#             (surchargeable : DEV_KEY_PATH=... scripts/build-release.sh)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS="$REPO/.secrets/phase-4a.env"
if [ ! -f "$SECRETS" ]; then
    echo "Erreur : $SECRETS absent (voir docs/superpowers/plans/2026-09-19-phase-4a-sync.md Task 4)" >&2
    exit 1
fi
# shellcheck disable=SC1090
source "$SECRETS"
: "${SUPABASE_URL:?SUPABASE_URL manquant dans .secrets/phase-4a.env}"
: "${DEVICE_KEY:?DEVICE_KEY manquant dans .secrets/phase-4a.env}"
BACKEND_URL="$SUPABASE_URL/functions/v1/sync"
KEY_PATH="${DEV_KEY_PATH:-$HOME/keys/developer_key.der}"
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp -R "$REPO/watch/connect-iq" "$TMP/app"

python3 - "$TMP/app/resources/settings.xml" "$BACKEND_URL" "$DEVICE_KEY" <<'EOF'
import sys
path, url, key = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
s = s.replace('<property id="backendUrl" type="string"/>',
              '<property id="backendUrl" type="string">' + url + '</property>')
s = s.replace('<property id="deviceKey" type="string"/>',
              '<property id="deviceKey" type="string">' + key + '</property>')
open(path, 'w').write(s)
EOF

OUT="$REPO/watch/connect-iq/sideload"
mkdir -p "$OUT"
for DEV in epix2pro51mm fr55; do
    "$SDK/bin/monkeyc" -d "$DEV" -f "$TMP/app/monkey.jungle" \
        -o "$OUT/badmintonscore-$DEV.prg" -y "$KEY_PATH" -w -r
    echo "OK : $OUT/badmintonscore-$DEV.prg"
done
echo "Prêt à sideloader : copie le .prg dans GARMIN/Apps/ de la montre."
